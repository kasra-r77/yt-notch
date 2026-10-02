#!/bin/bash
# Builds a release disk image in dist/. Its layout is design spec D6's and needs create-dmg;
# without it the image is plain. The app is signed ad hoc and isn't notarised
# (docs/decisions.md).
#
# EXPECTED_VERSION, when set, must match the app's version.
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
for notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
  [[ -f "$app/Contents/Resources/$notice" ]] || { echo "error: the app is missing $notice" >&2; exit 1; }
done
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
