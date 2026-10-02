#!/usr/bin/env python3
"""Create an audited, ad-hoc signed local package using the approved installed FFmpeg.
No installations, downloads, credentials or removal of existing releases.
"""
import argparse, datetime, hashlib, json, platform, plistlib, re, shutil, subprocess
from pathlib import Path

def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)

def dependencies(binary):
    return [line.strip().split(' (compatibility')[0] for line in run('otool','-L',str(binary)).splitlines()[1:] if ' (compatibility' in line]

def resolve_dependency(dependency, binary, executable):
    if dependency.startswith('/'): return Path(dependency).resolve()
    if dependency.startswith('@loader_path/'): return (binary.parent/dependency[len('@loader_path/'):]).resolve()
    if dependency.startswith('@executable_path/'): return (executable.parent/dependency[len('@executable_path/'):]).resolve()
    if dependency.startswith('@rpath/'):
        commands=run('otool','-l',str(binary))
        for rpath in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset',commands):
            rpath=rpath.replace('@loader_path',str(binary.parent)).replace('@executable_path',str(executable.parent))
            candidate=Path(rpath)/dependency[len('@rpath/'):]
            if candidate.exists(): return candidate.resolve()
    raise RuntimeError(f'Cannot resolve {dependency} in {binary}')

parser=argparse.ArgumentParser();parser.add_argument('--app',required=True,type=Path);parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parent.parent/'releases')
args=parser.parse_args(); source=args.app.resolve(); arch=platform.machine()
if not source.is_dir(): raise RuntimeError(f'Missing app bundle: {source}')
ffmpeg=Path('/opt/homebrew/bin/ffmpeg' if arch=='arm64' else '/usr/local/bin/ffmpeg').resolve()
if not ffmpeg.exists(): raise RuntimeError('The approved FFmpeg executable is required')
version=plistlib.loads((source/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
name=f'Trance-{version}-local-{arch}-{datetime.datetime.now().strftime("%Y%m%d-%H%M%S")}'
release=args.output.resolve()/name;release.mkdir(parents=True,exist_ok=False)
staging=release/'Install';staging.mkdir();bundle=staging/'Trance.app';shutil.copytree(source,bundle)
contents=bundle/'Contents';helpers=contents/'Helpers';frameworks=contents/'Frameworks';licenses=contents/'Resources/ThirdParty'
for folder in [helpers,frameworks,licenses]: folder.mkdir(parents=True,exist_ok=True)
exe=contents/'MacOS/Trance'
arches=run('lipo','-archs',str(exe)).split()
if arch not in arches: raise RuntimeError(f'App lacks host architecture {arch}')
if len(arches)>1:
    thin=exe.with_name('Trance.thin');run('lipo',str(exe),'-thin',arch,'-output',str(thin));thin.replace(exe)
files={ffmpeg:helpers/'ffmpeg'};pending=[ffmpeg];graphs={};formulas=set()
while pending:
    original=pending.pop(); graph=[]
    if arch not in run('lipo','-archs',str(original)).split(): raise RuntimeError(f'Helper dependency lacks {arch}: {original}')
    id_lines = run("otool", "-D", str(original)).splitlines()
    install_id = id_lines[1].strip() if len(id_lines) > 1 else None
    for dep in dependencies(original):
        if dep == install_id: continue
        if dep.startswith('/System/') or dep.startswith('/usr/lib/'): continue
        resolved=resolve_dependency(dep,original,ffmpeg)
        if resolved==original: continue
        if not resolved.is_file(): raise RuntimeError(f'Missing dependency: {resolved}')
        if resolved not in files:
            destination=frameworks/resolved.name
            if destination in files.values(): raise RuntimeError(f'Dependency filename collision: {resolved}')
            files[resolved]=destination;pending.append(resolved)
        graph.append((dep,resolved))
    graphs[original]=graph
for original,destination in files.items():
    shutil.copy2(original,destination)
    for dep,resolved in graphs[original]:
        replacement=('@loader_path/../Frameworks/' if destination.parent==helpers else '@loader_path/')+files[resolved].name
        run('install_name_tool','-change',dep,replacement,str(destination))
    if destination.parent==frameworks: run('install_name_tool','-id','@rpath/'+destination.name,str(destination))
    # Remove absolute Homebrew runpaths, which are obsolete after rewriting references.
    for rpath in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset',run('otool','-l',str(destination))):
        if '/homebrew/' in rpath or '/Cellar/' in rpath: run('install_name_tool','-delete_rpath',rpath,str(destination))
    parts=original.parts
    if 'Cellar' in parts:
        i=parts.index('Cellar');formula=Path(*parts[:i+3]);formulas.add(formula)
for formula in sorted(formulas):
    target=licenses/formula.parent.name;target.mkdir(exist_ok=True)
    for file in formula.iterdir():
        if file.is_file() and (re.search('LICENSE|COPYING|NOTICE',file.name,re.I) or file.name=='INSTALL_RECEIPT.json'): shutil.copy2(file,target/file.name)
minimum = plistlib.loads((contents/'Info.plist').read_bytes()).get('LSMinimumSystemVersion','15.0')
def version_key(value): return tuple(int(part) for part in value.split('.'))
for binary in files.values():
    for value in re.findall(r'\bminos ([0-9.]+)', run('vtool','-show-build',str(binary))):
        if version_key(value) > version_key(minimum): minimum = value
info = plistlib.loads((contents/'Info.plist').read_bytes()); info['LSMinimumSystemVersion'] = minimum
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
manifest=[]
for original,destination in files.items():
    remaining=[dep for dep in dependencies(destination) if dep.startswith('/') and not dep.startswith(('/System/','/usr/lib/'))]
    if remaining: raise RuntimeError(f'Nonportable dependencies remain: {remaining}')
    run('codesign','--force','--sign','-',str(destination))
    manifest.append({'file':str(destination.relative_to(bundle)),'source':str(original),'sha256':hashlib.sha256(destination.read_bytes()).hexdigest()})
root=Path(__file__).resolve().parents[2]
shutil.copy2(root/'trance-original-windows-dotnet/LICENSE',contents/'Resources/Original-LICENSE.txt')
(licenses/'manifest.json').write_text(json.dumps(manifest,indent=2))
(licenses/'LOCAL-USE.txt').write_text('This local package includes the existing GPL-enabled Homebrew FFmpeg and its installed runtime libraries. Installed license texts and build receipts accompany the binaries. Public distribution requires a separate corresponding-source/licensing review and Developer ID notarization. This package is prepared for local use only.\n')
run('codesign','--force','--sign','-',str(bundle));run('codesign','--verify','--deep','--strict','--verbose=2',str(bundle))
run(str(helpers/'ffmpeg'),'-version')
(staging/'Read Me.txt').write_text(f'Trance {version} — local {arch} package\n\nDrag Trance.app to Applications. Requires macOS {minimum} or later; this package contains the approved FFmpeg helper and its runtime libraries. No Homebrew installation is required.\n\nThis is an ad-hoc signed local build, not a Developer ID signed/notarized public release. Graphical/audio acceptance results and migration limitations are in the accompanying reports. Headset support remains deferred.\n')
(staging/'Applications').symlink_to('/Applications')
shutil.copytree(Path(__file__).resolve().parent.parent/'Reports',staging/'Reports')
for filename in ['MIGRATION.md','CHANGELOG.md']:
    shutil.copy2(Path(__file__).resolve().parent.parent/filename,staging/filename)
run('ditto','-c','-k','--sequesterRsrc','--keepParent',str(bundle),str(release/(name+'.zip')))
run('hdiutil','create','-volname','Trance Local','-srcfolder',str(staging),'-format','UDZO',str(release/(name+'.dmg')))
checksums={file.name:hashlib.sha256(file.read_bytes()).hexdigest() for file in release.iterdir() if file.is_file()}
(release/'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name,digest in checksums.items()))
print(release)
