#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Trance.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/Resources/Trance.icns" "$APP_BUNDLE/Contents/Resources/Trance.icns"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target "$ARCH-apple-macos15.0" -sdk "$SDK" "$ROOT_DIR"/App/*.swift "$ROOT_DIR"/Views/*.swift "$ROOT_DIR"/Models/*.swift "$ROOT_DIR"/Stores/*.swift "$ROOT_DIR"/Services/*.swift "$ROOT_DIR"/Support/*.swift -o "$APP_BUNDLE/Contents/MacOS/Trance"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Trance</string>
<key>CFBundleIdentifier</key><string>org.trance.mac</string>
<key>CFBundleIconFile</key><string>Trance.icns</string>
<key>CFBundleName</key><string>Trance</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf '%s\n' "$APP_BUNDLE"
