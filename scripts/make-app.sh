#!/bin/zsh
# Package a release build into dist/Cruft.app
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=dist/Cruft.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CruftApp "$APP/Contents/MacOS/Cruft"
cp Assets/Cruft.icns "$APP/Contents/Resources/Cruft.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cruft</string>
  <key>CFBundleDisplayName</key><string>Cruft</string>
  <key>CFBundleIdentifier</key><string>dev.noddle.cruft</string>
  <key>CFBundleExecutable</key><string>Cruft</string>
  <key>CFBundleIconFile</key><string>Cruft</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
