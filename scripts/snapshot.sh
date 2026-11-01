#!/bin/bash
# Usage: scripts/snapshot.sh [--baseline | --diff [--allow-diff]] [outdir]
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=run; ALLOW=0; OUT=""
for a in "$@"; do case "$a" in
  --baseline) MODE=baseline;; --diff) MODE=diff;; --allow-diff) ALLOW=1;; *) OUT="$a";; esac; done
if [ "$MODE" = diff ] && ! command -v magick >/dev/null; then
  echo "magick not found. Install: brew install imagemagick"; exit 2
fi
case "$MODE" in baseline) OUT=build/snapshots/baseline;; *) OUT="${OUT:-build/snapshots}";; esac
./scripts/build.sh >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT"
"build/Build/Products/${CONFIG:-Debug}/AmazonMusic.app/Contents/MacOS/AmazonMusic" --snapshot "$OUT"
[ "$MODE" = diff ] || exit 0
BASE=build/snapshots/baseline; bad=0
for b in "$BASE"/*.png; do
  f=$(basename "$b")
  if [ ! -f "$OUT/$f" ]; then echo "MISSING $f"; bad=1; continue; fi
  n=$(magick compare -metric AE -fuzz 8% "$b" "$OUT/$f" null: 2>&1 || true)
  n=${n%% *}; echo "$n $f"
  [ "$n" = 0 ] || bad=1
done
for c in "$OUT"/*.png; do [ -f "$BASE/$(basename "$c")" ] || { echo "EXTRA $(basename "$c")"; bad=1; }; done
[ "$bad" = 0 ] || [ "$ALLOW" = 1 ] || exit 1
