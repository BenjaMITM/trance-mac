#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Trance"
BUNDLE_ID="org.trance.mac"
APP_BUNDLE="$ROOT_DIR/build/Build/Products/Debug/Trance.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
case "$MODE" in run|--debug|--logs|--telemetry|--verify|--build-only) ;; *) echo "usage: $0 [--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2;; esac
if [[ "$MODE" != "--build-only" ]]; then pkill -x "$APP_NAME" >/dev/null 2>&1 || true; fi
xcodebuild -project "$ROOT_DIR/Trance.xcodeproj" -scheme Trance -configuration Debug -derivedDataPath "$ROOT_DIR/build" CODE_SIGNING_ALLOWED=NO build
case "$MODE" in
 --build-only) ;;
 --debug) lldb -- "$APP_BINARY" ;;
 --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
 --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
 --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
 run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
