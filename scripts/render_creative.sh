#!/usr/bin/env bash
# Render the App Store header and search results images from internal/creative/{header,search}.html.
# Each output is the universal 16:9 spec: 5244x2950 PNG without alpha.
set -euo pipefail

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
DIR="$(cd "$(dirname "$0")/../internal/creative" && pwd)"

for name in header search; do
  out="$DIR/$name-16x9.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files --force-device-scale-factor=2 \
    --window-size=2622,1475 --screenshot="$out" "file://$DIR/$name.html" >/dev/null 2>&1

  info=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$out")
  width=$(awk '/pixelWidth/ {print $2}' <<<"$info")
  height=$(awk '/pixelHeight/ {print $2}' <<<"$info")
  alpha=$(awk '/hasAlpha/ {print $2}' <<<"$info")
  if [ "$width" != 5244 ] || [ "$height" != 2950 ] || [ "$alpha" != no ]; then
    echo "$out: expected 5244x2950 without alpha, got ${width}x${height} alpha=$alpha" >&2
    exit 1
  fi
  echo "rendered $out"
done
