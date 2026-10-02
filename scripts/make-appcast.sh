#!/bin/bash
# Makes the update feed for a release (R5.2): signs the disk image with the private update
# key and writes dist/appcast.xml, with one item pointing at the image on the tag's GitHub
# release. Run it after scripts/make-dmg.sh, which leaves the app and Sparkle's tools in
# build/release. The release workflow runs it for version tags once the key exists.
#
#   SPARKLE_PRIVATE_KEY=<private key> scripts/make-appcast.sh dist/YT-Notch-0.2.0.dmg v0.2.0
#
# The app must carry the matching public key (SUPublicEDKey in project.yml), or it would
# ignore the feed: the README's "Updates" section has the steps.
set -euo pipefail
cd "$(dirname "$0")/.."

dmg="$1"
tag="$2"
: "${SPARKLE_PRIVATE_KEY:?set SPARKLE_PRIVATE_KEY to the private update key}"
app="build/release/Build/Products/Release/YT Notch.app"
tools="build/release/SourcePackages/artifacts/sparkle/Sparkle/bin"

key=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$app/Contents/Info.plist" 2>/dev/null || true)
if [[ -z "$key" ]]; then
  echo "error: the app has no SUPublicEDKey; add the public update key to project.yml (README, \"Updates\")" >&2
  exit 1
fi

# generate_appcast reads every archive in a folder; this one holds only the new image.
feed=$(mktemp -d)
trap 'rm -rf "$feed"' EXIT
cp "$dmg" "$feed/"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - \
  --download-url-prefix "https://github.com/kasra-r77/yt-notch/releases/download/$tag/" \
  --link "https://github.com/kasra-r77/yt-notch" \
  -o dist/appcast.xml "$feed"

grep -q 'sparkle:edSignature' dist/appcast.xml || { echo "error: the feed came out unsigned" >&2; exit 1; }
echo dist/appcast.xml
