#!/usr/bin/env bash
# Copy screenshots into the layout fastlane deliver expects.
# Source of truth is internal/screenshot; fastlane/screenshots is generated.
set -euo pipefail

SRC="internal/screenshot"
DEST="fastlane/screenshots/ko"

rm -rf "$DEST"
mkdir -p "$DEST"

for n in 1 2 3 4 5 6 7; do
  cp "$SRC/iPhone$n.png" "$DEST/iphone69_0${n}_iPhone$n.png"
  cp "$SRC/iPad$n.png" "$DEST/ipad13_0${n}_iPad$n.png"
done

count=$(find "$DEST" -name '*.png' | wc -l | tr -d ' ')
if [ "$count" -ne 14 ]; then
  echo "expected 14 screenshots, staged $count" >&2
  exit 1
fi
echo "staged $count screenshots into $DEST"
