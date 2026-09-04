#!/usr/bin/env bash
# Build Echoform.app (Release, arm64) and wrap it in a UDZO DMG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="Echoform"
VERSION="0.4.0"
mkdir -p "$DIST"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. This script must run on macOS with Xcode."
  exit 1
fi

xcodebuild \
  -project "$ROOT/Echoform.xcodeproj" \
  -scheme Echoform \
  -configuration Release \
  -destination "generic/platform=macOS" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  -derivedDataPath "$ROOT/build" \
  build

APP="$ROOT/build/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
  echo "Build succeeded but $APP is missing."
  exit 1
fi
test -x "$APP/Contents/MacOS/${APP_NAME}"

STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil imageinfo "$DMG" | head
echo "Wrote $DMG"
ls -lah "$DMG"
