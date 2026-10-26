#!/usr/bin/env bash
# Copy screenshots into the layout fastlane deliver expects.
# Source of truth is internal/screenshot/<set>/NN-<cut>.png; fastlane/screenshots is generated.
# deliver picks each file's display type from its pixel size, and orders files by name.
set -euo pipefail

SRC="internal/screenshot"
DEST="fastlane/screenshots/ko"
SETS=(iphone69 iphone63 iphoneduo ipad13)
CUTS=7

rm -rf "$DEST"
mkdir -p "$DEST"

for set in "${SETS[@]}"; do
  count=0
  for file in "$SRC/$set"/*.png; do
    [ -e "$file" ] || break
    cp "$file" "$DEST/${set}_$(basename "$file")"
    count=$((count + 1))
  done
  if [ "$count" -ne "$CUTS" ]; then
    echo "$set: expected $CUTS screenshots, found $count" >&2
    exit 1
  fi
done

total=$(find "$DEST" -name '*.png' | wc -l | tr -d ' ')
echo "staged $total screenshots into $DEST"
