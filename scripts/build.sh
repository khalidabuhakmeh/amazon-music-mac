#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OPEN=0; SELFTEST=0
for a in "$@"; do case "$a" in --open) OPEN=1;; --selftest) SELFTEST=1;; *) echo "unknown flag $a"; exit 64;; esac; done
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
APP="build/Build/Products/${CONFIG:-Debug}/AmazonMusic.app"
if [ "$SELFTEST" = 1 ]; then
  "$APP/Contents/MacOS/AmazonMusic" --selftest
  tools/grid-lint.sh
fi
if [ "$OPEN" = 1 ]; then
  mkdir -p ~/Applications
  pkill -x AmazonMusic || true
  sleep 0.5
  rm -rf ~/Applications/AmazonMusic.app
  cp -R "$APP" ~/Applications/AmazonMusic.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted ~/Applications/AmazonMusic.app
  # The agent CLI: the app binary under a short name on PATH.
  mkdir -p ~/.local/bin
  ln -sf ~/Applications/AmazonMusic.app/Contents/MacOS/AmazonMusic ~/.local/bin/amazonmusic
  open ~/Applications/AmazonMusic.app
fi
