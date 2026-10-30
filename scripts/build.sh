#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  echo "xcodegen not found. Install: brew install xcodegen"; exit 1
fi
xcodegen generate
# Keep build products out of Spotlight so they don't show up as duplicate apps.
mkdir -p build && touch build/.metadata_never_index
# Version shown in About: latest tag (v1.2.3 -> 1.2.3) and the commit count as the build number.
VERSION=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
xcodebuild -scheme AmazonMusic -configuration "${CONFIG:-Debug}" -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  MARKETING_VERSION="${VERSION:-0.0.0}" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build
