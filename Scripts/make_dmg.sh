#!/usr/bin/env bash
# Build Echoform.app (Release, arm64) and wrap it in a UDIF DMG.
# Run on a Mac with Xcode + macOS 26/27 SDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="Echoform"
VERSION="0.1.0"
mkdir -p "$DIST"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Open Echoform.xcodeproj on a Mac with Xcode."
  echo "This script cannot produce a signed .app in a Linux sandbox."
  exit 1
fi

xcodebuild \
  -project "$ROOT/Echoform.xcodeproj" \
  -scheme Echoform \
  -configuration Release \
  -destination "generic/platform=macOS" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath "$ROOT/build" \
  CODE_SIGN_IDENTITY="-" \
  build

APP="$ROOT/build/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
  echo "Build succeeded but $APP is missing."
  exit 1
fi

STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Wrote $DMG"

# Notarization (optional, needs Developer ID + notarytool profile):
# xcrun notarytool submit "$DMG" --keychain-profile "AC_PASSWORD" --wait
# xcrun stapler staple "$DMG"
