#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Clipline.app
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Clipline"

[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clipline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [ "${1:-}" = "--dmg" ]; then
    rm -f build/Clipline.dmg
    hdiutil create -volname Clipline -srcfolder "$APP" -ov -format UDZO build/Clipline.dmg >/dev/null
    echo "Built build/Clipline.dmg"
fi
