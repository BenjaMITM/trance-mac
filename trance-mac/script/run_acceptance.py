#!/usr/bin/env python3
"""Run native acceptance from a clean snapshot to avoid Xcode coordination stalls."""
from pathlib import Path
import datetime, shutil, subprocess, tempfile
root=Path(__file__).resolve().parent.parent
snapshot=Path(tempfile.mkdtemp(prefix='trance-acceptance-'))
for name in ['App','Models','Services','Stores','Views','Support','Resources','AcceptanceTests','UITests','Trance.xcodeproj']:
    shutil.copytree(root/name,snapshot/name,ignore=shutil.ignore_patterns('xcuserdata'))
output=root/'build'/('acceptance-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));output.mkdir(parents=True,exist_ok=False)
command=['xcodebuild','test','-project',str(snapshot/'Trance.xcodeproj'),'-scheme','Trance','-configuration','Debug','-destination','platform=macOS','-derivedDataPath',str(output/'DerivedData'),'-resultBundlePath',str(output/'Results.xcresult'),'CODE_SIGNING_ALLOWED=NO']
with (output/'test.log').open('w') as log:
    result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
print('PASS' if result.returncode==0 else 'FAIL',output)
raise SystemExit(result.returncode)
