#!/bin/bash
# Builds the probe and replay binaries against the app sources under <source-root>.
# Usage: build.sh <source-root> <out-dir> [ROUTED]
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $0 <source-root> <out-dir> [ROUTED]" >&2
    exit 64
fi

here="$(cd "$(dirname "$0")" && pwd)"
services="$1/SnapLedger/Services"
out="$2"
flags=()
if [ "${3:-}" = "ROUTED" ]; then
    flags=(-D ROUTED)
fi

app="$out/app"
rm -rf "$app"
mkdir -p "$app"
for name in ExtractionService ExtractionService+Cleanup ExtractionService+Vision OCRLayout PaymentExtraction \
    Int+ZeroPadded CandidateHeuristics CandidateAutoFill CategoryValidation OCRService ResumeOnce; do
    if [ -f "$services/$name.swift" ]; then
        cp "$services/$name.swift" "$app/"
    fi
done
# The probe has no AppleIntelligenceStatus; macOS 27 with Apple Intelligence on is assumed.
sed -i '' 's/static var isAvailable: Bool { AppleIntelligenceStatus.current.isAvailable }/static var isAvailable: Bool { true }/' \
    "$app/ExtractionService.swift"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
compile() {
    xcrun swiftc -parse-as-library -O -target arm64-apple-macos27.0 -sdk "$sdk" ${flags[@]+"${flags[@]}"} "$@"
}
compile "$app"/*.swift "$here/probe/stubs.swift" "$here/probe/main.swift" -o "$out/probe"
compile "$app"/*.swift "$here/probe/stubs.swift" "$here/replay/main.swift" -o "$out/replay"
echo "built $out/probe $out/replay"
