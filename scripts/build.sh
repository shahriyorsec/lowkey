#!/bin/zsh
# Builds build/Lowkey.app. Pass --run to relaunch it afterwards,
# or --install to copy it to /Applications and launch it from there.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Lowkey.app
pkill -x Lowkey 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(swift build -c release --show-bin-path)/Lowkey"
cp "$BIN" "$APP/Contents/MacOS/Lowkey"
cp Support/Info.plist "$APP/Contents/Info.plist"
# The icon is drawn by the app's own code, so the bundled icon and the Settings previews always match.
rm -rf build/AppIcon.iconset
"$BIN" --export-iconset build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier app.lowkey.overlay "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then open "$APP"; fi
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Lowkey 2>/dev/null || true
  rm -rf /Applications/Lowkey.app
  cp -R "$APP" /Applications/Lowkey.app
  echo "Installed /Applications/Lowkey.app"
  open /Applications/Lowkey.app
fi
