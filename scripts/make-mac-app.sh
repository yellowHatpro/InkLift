#!/bin/sh
# Builds InkLiftMac and wraps it as InkLift.app. Default destination: ~/Applications.
#   scripts/make-mac-app.sh            -> ~/Applications/InkLift.app
#   scripts/make-mac-app.sh /Applications
set -e
cd "$(dirname "$0")/.."
DEST="${1:-$HOME/Applications}"
swift build -c release --product InkLiftMac
BIN=.build/release/InkLiftMac
RES=.build/release/InkLift_InkCore.bundle
APP="$DEST/InkLift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/InkLift"
# SwiftPM resources are looked up next to the executable.
cp -R "$RES" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>InkLift</string>
  <key>CFBundleDisplayName</key><string>InkLift</string>
  <key>CFBundleIdentifier</key><string>dev.ashutosh.inklift.mac</string>
  <key>CFBundleExecutable</key><string>InkLift</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.image</string></array>
  </dict></array>
</dict></plist>
EOF
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
