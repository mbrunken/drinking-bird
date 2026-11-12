#!/bin/bash
# Builds "Drinking Bird.app" next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP="Drinking Bird.app"
BIN="DrinkingBird"
BUILD=".build"

mkdir -p "$BUILD"
swiftc -O -swift-version 5 -parse-as-library \
  -framework SwiftUI -framework AppKit -framework ApplicationServices \
  Sources/main.swift -o "$BUILD/$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$BIN" "$APP/Contents/MacOS/$BIN"

# Generate the app icon by rendering the bird itself.
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
"$BUILD/$BIN" --render-icon "$BUILD/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Drinking Bird</string>
  <key>CFBundleDisplayName</key><string>Drinking Bird</string>
  <key>CFBundleIdentifier</key><string>local.drinkingbird</string>
  <key>CFBundleExecutable</key><string>DrinkingBird</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $(pwd)/$APP"
