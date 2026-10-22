#!/bin/bash
# Builds "Perch.app" into ./build using Apple's Swift compiler.
#   bash build.sh              (this Mac's chip)
#   UNIVERSAL=1 bash build.sh  (Apple silicon + Intel)
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's developer tools aren't installed. Run:  xcode-select --install"
  echo "then run this again."
  exit 1
fi

APP="build/Perch.app"
rm -rf "$APP" "build/Reolink Viewer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# Icons
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"

echo "Compiling…"
FLAGS=(-O -parse-as-library -swift-version 5)
if [ "${UNIVERSAL:-0}" = "1" ]; then
  for ARCH in arm64 x86_64; do
    xcrun -sdk macosx swiftc "${FLAGS[@]}" -target "$ARCH-apple-macos13.0" -o "build/Perch-$ARCH" Sources/*.swift
  done
  lipo -create -output "$APP/Contents/MacOS/Perch" build/Perch-arm64 build/Perch-x86_64
  rm -f build/Perch-arm64 build/Perch-x86_64
else
  xcrun -sdk macosx swiftc "${FLAGS[@]}" -target "$(uname -m)-apple-macos13.0" -o "$APP/Contents/MacOS/Perch" Sources/*.swift
fi

codesign --force --sign - "$APP" >/dev/null
echo ""
echo "Built: $(pwd)/$APP"
echo "Open it with:  open \"$APP\""
