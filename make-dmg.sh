#!/bin/bash
# Packages "Perch.app" into build/Perch.dmg for sharing.
#
#   bash make-dmg.sh
#
# Optional, for a DMG that opens without Gatekeeper warnings on other Macs
# (needs a paid Apple Developer account):
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="perch-notary" \
#   bash make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

# Build a universal app so it runs on Intel Macs too.
UNIVERSAL=1 bash build.sh

APP="build/Perch.app"
DMG="build/Perch.dmg"
STAGE="build/dmg-stage"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "Signing with: $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "Creating disk image…"
hdiutil create -volname "Perch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --sign "$DEVELOPER_ID" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Sending to Apple for notarisation (takes a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo ""
echo "Done: $(pwd)/$DMG"
