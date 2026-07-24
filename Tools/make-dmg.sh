#!/bin/bash
# Builds Release and packages a drag-to-install DMG.
#
#   Tools/make-dmg.sh [output.dmg]
#
# The app is ad-hoc signed (no Developer ID), so first launch on another Mac
# needs right-click → Open. Fine for personal/private distribution.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/QSOPartyLogger.dmg}"
VOLNAME="QSO Party Logger"

echo "==> Building Release"
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger \
    -configuration Release -destination 'platform=macOS' build \
    CONFIGURATION_BUILD_DIR="$PWD/build/Release" >/dev/null

APP="$PWD/build/Release/QSOPartyLogger.app"
[ -d "$APP" ] || { echo "Build produced no app at $APP" >&2; exit 1; }

echo "==> Staging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Give the mounted volume the app's own icon.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
    SetFile -a C "$STAGE" 2>/dev/null || true
fi

echo "==> Creating $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$OUT"

echo "==> Done: $OUT ($(du -h "$OUT" | cut -f1))"
