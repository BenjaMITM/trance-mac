#!/usr/bin/env python3
"""Register the checked-in native XCTest targets without third-party tooling."""
from pathlib import Path
import hashlib, re
root=Path(__file__).resolve().parent.parent
p=root/'Trance.xcodeproj/project.pbxproj'
s=p.read_text()
def ident(text): return hashlib.sha1(('acceptance:'+text).encode()).hexdigest()[:24].upper()
if 'name = TranceAudioTests;' not in s:
 entries=[]; targets=[]; products=[]; groups=[]
 refs={path:ref for ref,path in re.findall(r'(\w{24}) = \{isa = PBXFileReference;.*?path = "([^"]+)";',s)}
 for target,kind,files in [('TranceAudioTests','unit-test',sorted(str(f.relative_to(root)) for f in (root/'Models').glob('*.swift'))+['Services/AudioService.swift','Services/CodecService.swift','AcceptanceTests/AudioAcceptanceTests.swift']),('TranceUITests','ui-testing',['UITests/DesktopAcceptanceTests.swift'])]:
  tid=ident(target);prod=ident(target+'product');phase=ident(target+'sources');fw=ident(target+'frameworks');config=ident(target+'configs'); targets.append(tid);products.append(prod); buildrefs=[]
  for path in files:
   ref=refs.get(path)
   if ref is None:
    ref=ident(path);groups.append(ref);entries.append(f'{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "<group>";}};')
   build=ident(target+path);entries.append(f'{build} = {{isa = PBXBuildFile; fileRef = {ref};}};');buildrefs.append(build)
  entries.append(f'{prod} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {target}.xctest; sourceTree = BUILT_PRODUCTS_DIR;}};')
  deps=''
  if kind=='ui-testing':
   proxy=ident('proxy');dep=ident('dependency');deps=dep
   entries.extend([f'{proxy} = {{isa = PBXContainerItemProxy; containerPortal = 000000000000000000000001; proxyType = 1; remoteGlobalIDString = 000000000000000000000004; remoteInfo = Trance;}};',f'{dep} = {{isa = PBXTargetDependency; target = 000000000000000000000004; targetProxy = {proxy};}};'])
  entries.extend([f'{tid} = {{isa = PBXNativeTarget; buildConfigurationList = {config}; buildPhases = ({phase},{fw}); buildRules = (); dependencies = ({deps}); name = {target}; productName = {target}; productReference = {prod}; productType = "com.apple.product-type.bundle.{kind}";}};',f'{phase} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(buildrefs)}); runOnlyForDeploymentPostprocessing = 0;}};',f'{fw} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}};'])
  configs=[]
  for mode in ['Debug','Release']:
   cid=ident(target+mode);configs.append(cid)
   settings=f'PRODUCT_NAME = {target}; PRODUCT_BUNDLE_IDENTIFIER = org.trance.mac.{target}; GENERATE_INFOPLIST_FILE = YES; SWIFT_VERSION = 6.0; MACOSX_DEPLOYMENT_TARGET = 15.0; SDKROOT = macosx; CODE_SIGN_STYLE = Automatic; SWIFT_OPTIMIZATION_LEVEL = "-Onone";'
   if kind=='ui-testing': settings+=' TEST_TARGET_NAME = Trance;'
   entries.append(f'{cid} = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {mode};}};')
  entries.append(f'{config} = {{isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;}};')
 s=s.replace('objects = {\n','objects = {\n'+'\n'.join(entries)+'\n')
 s=s.replace('targets = (000000000000000000000004);','targets = (000000000000000000000004,'+','.join(targets)+');')
 s=s.replace('children = (000000000000000000000005);','children = (000000000000000000000005,'+','.join(products)+');')
 s=s.replace('000000000000000000000002 = {isa = PBXGroup; children = (','000000000000000000000002 = {isa = PBXGroup; children = ('+','.join(groups)+',')
 p.write_text(s)
scheme=root/'Trance.xcodeproj/xcshareddata/xcschemes/Trance.xcscheme'
s=scheme.read_text()
if '<Testables>' not in s:
 tests=''.join(f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(t)}" BuildableName="{t}.xctest" BlueprintName="{t}" ReferencedContainer="container:Trance.xcodeproj"/></TestableReference>' for t in ['TranceAudioTests','TranceUITests'])
 s=s.replace('<TestAction buildConfiguration="Debug"/>',f'<TestAction buildConfiguration="Debug"><Testables>{tests}</Testables></TestAction>');scheme.write_text(s)
