#!/bin/bash
# Builds the release archive dist/BetterFinder-v<VERSION>.zip.
# It does not tag, push or publish anything.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
ZIP="dist/BetterFinder-v$VERSION.zip"

swift test
scripts/bundle.sh release

rm -f "$ZIP"
ditto -c -k --keepParent dist/BetterFinder.app "$ZIP"
echo "Created $ZIP"
shasum -a 256 "$ZIP"
