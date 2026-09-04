#!/usr/bin/env bash
# Build Echoform.app and wrap it in an HFS+ UDZO DMG that Finder mounts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="Echoform"
VERSION="0.4.1"
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
file "$APP/Contents/MacOS/${APP_NAME}"
ls -lah "$APP/Contents/MacOS/${APP_NAME}"

STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# HFS+ not APFS — DiskImageMounter is more reliable with this layout.
DMG="$DIST/${APP_NAME}.dmg"
rm -f "$DMG" "$DIST/${APP_NAME}-${VERSION}.dmg"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  -layout NONE \
  "$DMG"

# Must actually mount, and the volume must contain the .app
MNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT"
test -d "$MNT/${APP_NAME}.app"
test -x "$MNT/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
ls -la "$MNT"
hdiutil detach "$MNT" -force

cp -f "$DMG" "$DIST/${APP_NAME}-${VERSION}.dmg"
ditto -c -k --keepParent "$APP" "$DIST/${APP_NAME}.app.zip"

hdiutil imageinfo "$DMG" | head -20
echo "Wrote $DMG"
ls -lah "$DIST"
