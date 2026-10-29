#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  echo "xcodegen not found. Install: brew install xcodegen"; exit 1
fi
xcodegen generate
# Keep build products out of Spotlight so they don't show up as duplicate apps.
mkdir -p build && touch build/.metadata_never_index
xcodebuild -scheme AmazonMusic -configuration "${CONFIG:-Debug}" -destination 'platform=macOS,arch=arm64' -derivedDataPath build build
