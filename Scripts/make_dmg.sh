#!/usr/bin/env bash
# Build Echoform.app, ad-hoc sign it (no restricted entitlements), wrap in HFS+ UDZO.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="Echoform"
VERSION="0.4.2"
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
  CODE_SIGNING_REQUIRED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  ENABLE_APP_SANDBOX=NO \
  DEVELOPMENT_TEAM= \
  -derivedDataPath "$ROOT/build" \
  build

APP="$ROOT/build/Build/Products/Release/${APP_NAME}.app"
test -d "$APP"
test -x "$APP/Contents/MacOS/${APP_NAME}"

# Re-sign ad-hoc WITHOUT restricted entitlements (sandbox / nearby-interaction
# on an ad-hoc cert = instant kill by AMFI, "app won't open").
codesign --force --deep --sign - "$APP"
codesign -dv --verbose=2 "$APP" || true

STAGE="$DIST/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/ÖFFNEN.command" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
xattr -cr "Echoform.app" 2>/dev/null || true
open "Echoform.app"
EOF
chmod +x "$STAGE/ÖFFNEN.command"

cat > "$STAGE/LIESMICH.txt" << 'TXT'
Echoform startet nicht per Doppelklick, wenn Gatekeeper meckert.

1. ÖFFNEN.command doppelklicken
   oder
2. Echoform.app: Rechtsklick → Öffnen → Öffnen
   oder
3. Terminal:
   xattr -cr /Applications/Echoform.app
   open /Applications/Echoform.app

Apple silicon. Ohne Apple-Developer-ID, daher nicht notarisiert.
TXT

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

MNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT"
test -d "$MNT/${APP_NAME}.app"
test -x "$MNT/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
# App must not carry restricted entitlements
codesign -d --entitlements :- "$MNT/${APP_NAME}.app" 2>/dev/null | tee /tmp/ents.xml || true
if grep -q 'app-sandbox\|nearby-interaction' /tmp/ents.xml 2>/dev/null; then
  echo "FATAL: restricted entitlements still embedded"
  cat /tmp/ents.xml
  exit 1
fi
ls -la "$MNT"
hdiutil detach "$MNT" -force

cp -f "$DMG" "$DIST/${APP_NAME}-${VERSION}.dmg"
ditto -c -k --keepParent "$APP" "$DIST/${APP_NAME}.app.zip"
echo "Wrote $DMG"
ls -lah "$DIST"
