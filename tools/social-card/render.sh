#!/bin/sh
# Renders tools/social-card/card.html to docs/social-card.png (1280x640)
# using headless Google Chrome.
set -e
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
OUT="$(cd ../../docs && pwd)/social-card.png"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1280,640 \
  --allow-file-access-from-files \
  --screenshot="$OUT" "file://$(pwd)/card.html" >/dev/null 2>&1
echo "Wrote $OUT"
