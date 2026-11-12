#!/bin/bash
# Builds BetterFinder and assembles dist/BetterFinder.app (signed with the local certificate, or ad hoc).
# Usage: scripts/bundle.sh [release|debug] [output folder]
# The output folder defaults to dist/. Building elsewhere leaves a running
# copy of dist/BetterFinder.app untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
OUT="${2:-dist}"
APP="$OUT/BetterFinder.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fr.lproj"
cp "$BIN/BetterFinder" "$APP/Contents/MacOS/BetterFinder"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" \
    Resources/Info.plist.template > "$APP/Contents/Info.plist"
# An (even empty) fr.lproj makes macOS show the standard menus in French.
printf '/* French is the only localization. */\n' \
    > "$APP/Contents/Resources/fr.lproj/InfoPlist.strings"

# A stable identity keeps the privacy permissions (Full Disk Access...) valid
# from one build to the next: macOS ties them to the signature, which changes
# every time with an ad hoc one. "BetterFinder Local" is a self-signed code
# signing certificate in the login keychain; without it, sign ad hoc.
if security find-certificate -c "BetterFinder Local" >/dev/null 2>&1; then
    codesign --force --sign "BetterFinder Local" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP (version $VERSION, build $BUILD, $CONFIG)"
