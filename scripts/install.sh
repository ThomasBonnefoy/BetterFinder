#!/bin/bash
# Builds BetterFinder and installs it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh release

DEST="/Applications/BetterFinder.app"
if pgrep -xq BetterFinder; then
    echo "BetterFinder is running: quit it first, then run this script again." >&2
    exit 1
fi
rm -rf "$DEST"
cp -R dist/BetterFinder.app "$DEST"
echo "Installed $DEST"
