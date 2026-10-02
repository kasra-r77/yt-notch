#!/bin/bash
# Builds YT Notch for release and packs it into a disk image in dist/, laid out as D6 has it:
# a 660 × 400 window on docs/design/brand/dmg-background, the app at (165, 180) and the
# Applications link at (495, 180), both at 128. That layout needs create-dmg
# (`brew install create-dmg`); without it the image is plain, with the same two items.
#
# The app is signed ad hoc, not with a Developer ID, and isn't notarised (see
# docs/decisions.md): macOS asks once before opening it, as the README explains.
#
# EXPECTED_VERSION, when set (the release workflow sets it from the tag), must match the
# app's version.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -scheme YTNotch -configuration Release -derivedDataPath build/release \
  -destination 'generic/platform=macOS' -quiet build

app="build/release/Build/Products/Release/YT Notch.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ -n "${EXPECTED_VERSION:-}" && "$EXPECTED_VERSION" != "$version" ]]; then
  echo "error: the tag says $EXPECTED_VERSION, but the app is version $version (MARKETING_VERSION in project.yml)" >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
lipo -archs "$app/Contents/MacOS/YT Notch"

mkdir -p dist
dmg="dist/YT-Notch-$version.dmg"
rm -f "$dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"

if command -v create-dmg >/dev/null; then
  # One background with both resolutions, so Retina screens get the sharp one.
  tiffutil -cathidpicheck docs/design/brand/dmg-background.png docs/design/brand/dmg-background@2x.png \
    -out "$stage/../dmg-background.tiff" >/dev/null
  create-dmg \
    --volname "YT Notch" \
    --background "$stage/../dmg-background.tiff" \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "YT Notch.app" 165 180 \
    --app-drop-link 495 180 \
    --hide-extension "YT Notch.app" \
    --no-internet-enable \
    "$dmg" "$stage"
  rm -f "$stage/../dmg-background.tiff"
else
  echo "note: create-dmg isn't installed, so the disk image is plain (brew install create-dmg for D6's layout)" >&2
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "YT Notch" -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
fi

hdiutil verify "$dmg" >/dev/null
echo "$dmg"
