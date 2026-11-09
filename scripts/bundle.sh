#!/bin/bash
# Builds BetterFinder and assembles dist/BetterFinder.app (ad hoc signed).
# Usage: scripts/bundle.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/BetterFinder.app"

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

codesign --force --sign - "$APP"
echo "Built $APP (version $VERSION, build $BUILD, $CONFIG)"
