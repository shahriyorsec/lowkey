#!/bin/zsh
# Builds build/Lowkey.app. Pass --run to relaunch it afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Lowkey.app
pkill -x Lowkey 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Lowkey" "$APP/Contents/MacOS/Lowkey"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier app.lowkey.overlay "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then open "$APP"; fi
