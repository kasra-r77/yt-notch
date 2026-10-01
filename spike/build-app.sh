#!/bin/bash
# Builds the throwaway spike as a signed (ad hoc) .app, so WebKit's default
# data store is tied to a real bundle identifier and survives relaunches.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/YTNotchSpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/YTNotchSpike "$APP/Contents/MacOS/YTNotchSpike"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.kasra-r77.ytnotch.spike</string>
    <key>CFBundleName</key>
    <string>YT Notch spike</string>
    <key>CFBundleExecutable</key>
    <string>YTNotchSpike</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
