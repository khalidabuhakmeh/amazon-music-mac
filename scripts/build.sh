#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  echo "xcodegen not found. Install: brew install xcodegen"; exit 1
fi
xcodegen generate
xcodebuild -scheme AmazonMusic -configuration "${CONFIG:-Debug}" -destination 'platform=macOS,arch=arm64' -derivedDataPath build build
