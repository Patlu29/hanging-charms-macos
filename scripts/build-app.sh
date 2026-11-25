#!/usr/bin/env bash
# Builds "Hanging Charms.app" from the Swift package and ad-hoc signs it.
#
#   ./scripts/build-app.sh            # release build into ./dist
#   CONFIG=debug ./scripts/build-app.sh
#
# The result runs from anywhere. Move it to /Applications for launch at login.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="Hanging Charms"
EXEC="HangingCharms"
BUNDLE_ID="${BUNDLE_ID:-com.hangingcharms.mac}"
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building $EXEC ($CONFIG, universal)"
swift build -c "$CONFIG" --arch arm64 --arch x86_64 --product "$EXEC"
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC" "$APP/Contents/MacOS/$EXEC"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT Licence. Original charm artwork.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --timestamp=none "$APP"

echo "==> Zipping"
(cd "$DIST" && rm -f "HangingCharms-$VERSION.zip" && ditto -c -k --keepParent "$APP_NAME.app" "HangingCharms-$VERSION.zip")

echo "Built: $APP"
echo "Zip:   $DIST/HangingCharms-$VERSION.zip"
