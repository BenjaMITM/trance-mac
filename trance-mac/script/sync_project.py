#!/usr/bin/env python3
"""Add native Swift sources to the checked-in Xcode project without dependencies."""
from pathlib import Path
import hashlib, re
root = Path(__file__).resolve().parent.parent
project = root / 'Trance.xcodeproj/project.pbxproj'
text = project.read_text()
for folder in ['App','Views','Models','Stores','Services','Support']:
    for file in sorted((root/folder).glob('*.swift')):
        path = file.relative_to(root).as_posix()
        if 'path = "'+path+'"' in text:
            continue
        ref = hashlib.sha1(path.encode()).hexdigest()[:24].upper()
        build = hashlib.sha1(('build'+path).encode()).hexdigest()[:24].upper()
        entries = f'{build} = {{isa = PBXBuildFile; fileRef = {ref}; }};\n{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = "<group>"; }};\n'
        text = text.replace('objects = {\n','objects = {\n'+entries)
        text = text.replace('000000000000000000000002 = {isa = PBXGroup; children = (','000000000000000000000002 = {isa = PBXGroup; children = ('+ref+',')
        text = text.replace('000000000000000000000006 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (','000000000000000000000006 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+build+',')
project.write_text(text)
