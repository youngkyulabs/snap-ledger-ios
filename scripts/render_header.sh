#!/usr/bin/env bash
# Render the App Store header/search results asset from internal/creative/header.html.
# Output is the universal 16:9 spec: 5244x2950 PNG without alpha.
set -euo pipefail

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SRC="$(cd internal/creative && pwd)/header.html"
OUT="internal/creative/universal-16x9.png"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --allow-file-access-from-files --force-device-scale-factor=2 \
  --window-size=2622,1475 --screenshot="$OUT" "file://$SRC" >/dev/null 2>&1

info=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT")
width=$(awk '/pixelWidth/ {print $2}' <<<"$info")
height=$(awk '/pixelHeight/ {print $2}' <<<"$info")
alpha=$(awk '/hasAlpha/ {print $2}' <<<"$info")
if [ "$width" != 5244 ] || [ "$height" != 2950 ] || [ "$alpha" != no ]; then
  echo "expected 5244x2950 without alpha, got ${width}x${height} alpha=$alpha" >&2
  exit 1
fi
echo "rendered $OUT"
