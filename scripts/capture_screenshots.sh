#!/usr/bin/env bash
# Capture the App Store screenshot sets into internal/screenshot/<set>/.
# Usage: scripts/capture_screenshots.sh [set ...]   (default: every set below)
set -euo pipefail

cd "$(dirname "$0")/.."

# set name | simulator name | accepted pixel sizes
SETS=(
  "iphone69|iPhone 18 Pro Max|1320x2868"
  "iphone63|iPhone 18 Pro|1206x2622"
  "iphoneduo|iPhone Duo|2007x2853 2853x2007 1398x2034 2034x1398"
  "ipad13|iPad Pro 13-inch (M5)|2064x2752"
)
CUTS=7
BUNDLE_ID="com.youngkyu.snapledger"
DERIVED="build/screenshots"
OUT="internal/screenshot"

requested=("$@")
if [ ${#requested[@]} -eq 0 ]; then
  for entry in "${SETS[@]}"; do requested+=("${entry%%|*}"); done
fi

# Newest iOS runtime that has an available simulator with exactly this name.
udid_for() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    for device in devices:
        if device["name"] == name:
            found.append(((int(match[1]), int(match[2])), device["udid"]))
if not found:
    sys.exit(f"no available simulator named {name!r}")
print(max(found)[1])
' "$1"
}

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

# Korean system language and region, so status bar dates match the app (iPad and Duo show them).
ensure_korean() {
  local languages
  languages=$(xcrun simctl spawn "$1" defaults read "Apple Global Domain" AppleLanguages 2>/dev/null | tr -d ' \n')
  if [ "$languages" != '("ko-KR")' ]; then
    xcrun simctl spawn "$1" defaults write "Apple Global Domain" AppleLanguages -array ko-KR
    xcrun simctl spawn "$1" defaults write "Apple Global Domain" AppleLocale -string ko_KR
    xcrun simctl shutdown "$1"
    boot "$1"
  fi
}

echo "Building for testing…"
xcodebuild build-for-testing -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" -quiet
xctestrun=$(find "$DERIVED/Build/Products" -name '*.xctestrun' | head -1)

for set in "${requested[@]}"; do
  entry=""
  for candidate in "${SETS[@]}"; do
    if [ "${candidate%%|*}" = "$set" ]; then entry="$candidate"; fi
  done
  if [ -z "$entry" ]; then
    echo "unknown set: $set" >&2
    exit 1
  fi
  IFS='|' read -r _ device sizes <<<"$entry"
  udid=$(udid_for "$device")
  echo "== $set: $device ($udid)"

  boot "$udid"
  ensure_korean "$udid"
  xcrun simctl ui "$udid" appearance light
  # Time string only: an ISO date makes the iPad status bar weekday disagree with the device date.
  # Clearing first matters: a stale override leaves the iPhone 18 Pro showing no-service dots.
  xcrun simctl status_bar "$udid" clear
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 \
    --dataNetwork wifi --cellularMode active --cellularBars 4 --operatorName ""
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" || true

  staging=$(mktemp -d)
  result="$DERIVED/$set.xcresult"
  rm -rf "$result"
  # No parallel testing: it would run on a clone that lacks the status bar and locale set above.
  if ! TEST_RUNNER_SCREENSHOT_DIR="$staging" TEST_RUNNER_SCREENSHOT_SET="$set" \
    xcodebuild test-without-building -xctestrun "$xctestrun" -destination "id=$udid" \
    -only-testing:SnapLedgerUITests/AppStoreScreenshotTests -parallel-testing-enabled NO \
    -collect-test-diagnostics never -resultBundlePath "$result" -quiet; then
    echo "$set: capture failed; see $result" >&2
    exit 1
  fi

  count=$(find "$staging" -name '*.png' | wc -l | tr -d ' ')
  if [ "$count" -ne "$CUTS" ]; then
    echo "$set: expected $CUTS screenshots, got $count" >&2
    exit 1
  fi
  for file in "$staging"/*.png; do
    size="$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')x$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')"
    case " $sizes " in
      *" $size "*) ;;
      *)
        echo "$set: $(basename "$file") is $size, expected one of: $sizes" >&2
        exit 1
        ;;
    esac
  done

  rm -rf "${OUT:?}/$set"
  mkdir -p "$OUT/$set"
  mv "$staging"/*.png "$OUT/$set/"
  rmdir "$staging"
  echo "$set: $count screenshots in $OUT/$set"
done
