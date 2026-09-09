#!/bin/sh
#
# Package a built MacLock.app for Sparkle: zip it, sign the zip with the EdDSA key in
# this Mac's login keychain, and write the appcast.xml that MacLock reads.
#
#   Scripts/generate-appcast.sh <path/to/MacLock.app> <output-dir> [download-url-prefix]
#
# The zip is named after the app's marketing version (MacLock-1.1.zip). The download
# URL prefix defaults to the GitHub release whose tag is that version with a "v" in
# front, which is where the README's release procedure says to upload the files. Pass
# a different prefix to test against a local server.
#
# generate_appcast comes from the Sparkle package Xcode resolved into DerivedData; set
# SPARKLE_BIN to point somewhere else if it lives elsewhere on the release machine.
#
# Signing reads the private key from the login keychain, which macOS guards with a
# password prompt the first time generate_appcast asks ("Always Allow" ends that). For
# an unattended run, export the key once with `generate_keys -x <file>` and set
# SPARKLE_ED_KEY_FILE to that file; keep it out of the repository.
set -eu

if [ $# -lt 2 ]; then
  echo "usage: $0 <path/to/MacLock.app> <output-dir> [download-url-prefix]" >&2
  exit 64
fi

APP=$1
OUT=$2

if [ ! -d "$APP/Contents" ]; then
  echo "error: $APP is not an app bundle" >&2
  exit 66
fi

PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
PREFIX=${3:-"https://github.com/yumaitau/MacLock/releases/download/v$VERSION/"}

if [ -z "${SPARKLE_BIN:-}" ]; then
  # Newest resolved copy wins if several DerivedData trees carry one.
  SPARKLE_BIN=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/MacLock-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -n 1 || true)
fi
if [ -z "$SPARKLE_BIN" ] || [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "error: Sparkle's generate_appcast not found. Build MacLock once in Xcode so the package resolves, or set SPARKLE_BIN." >&2
  exit 69
fi

mkdir -p "$OUT"
ARCHIVE="$OUT/MacLock-$VERSION.zip"

# ditto keeps the symlinks inside Sparkle.framework, which a zip that follows them
# would break -- and a broken framework signature is an update Sparkle refuses.
echo "Archiving $APP ($VERSION, build $BUILD) -> $ARCHIVE"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

echo "Signing and writing $OUT/appcast.xml"
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  set -- --ed-key-file "$SPARKLE_ED_KEY_FILE"
else
  set --
fi
"$SPARKLE_BIN/generate_appcast" "$@" \
  --download-url-prefix "$PREFIX" \
  --link "https://github.com/yumaitau/MacLock" \
  -o "$OUT/appcast.xml" \
  "$OUT"

echo "Done. Upload $(basename "$ARCHIVE") and appcast.xml to the release at ${PREFIX%/}"
