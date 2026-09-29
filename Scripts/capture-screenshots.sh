#!/bin/bash
# A08 pipeline: capture real Release-build screenshots on the required App Store
# slots (6.9" + 6.5" iPhone) and verify pixel dimensions per slot.
#
# Usage: Scripts/capture-screenshots.sh <output-dir>
#
# Final post-rebuild A08 set (9 shots covering S01/S02/S05/S06/S08/S10);
# see ScreenshotTests.swift. PNGs + manifest become docs/evidence/a08/.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${1:?Supply an output directory}"
out=$1
mkdir -p "$out"

device_69=${CUBEGUIDE_SHOT_DEVICE_69:-F3186141-1A3E-4C86-AC0A-E062E15F1F0E} # iPhone 16 Pro Max, iOS 18.5

device_65=$(xcrun simctl list devices available 2>/dev/null \
  | grep -E "CubeGuide screenshots 6.5in" | grep -oE "[0-9A-F-]{36}" | head -1 || true)
if [ -z "${device_65:-}" ]; then
  runtime=$(xcrun simctl list runtimes 2>/dev/null | grep -E "iOS .*18\.5" | grep -oE "com\.apple\.CoreSimulator\.SimRuntime\.iOS-18-5" | head -1)
  : "${runtime:?No iOS 18.5 runtime found}"
  device_65=$(xcrun simctl create "CubeGuide screenshots 6.5in" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max "$runtime")
  echo "created 6.5in device: $device_65"
fi

capture() {
  local udid=$1 slot=$2 width=$3 height=$4
  local dir="$out/$slot"
  mkdir -p "$dir"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcodebuild -project cubeguide.xcodeproj -scheme CubeGuideScreenshots \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "DerivedData-shots-$slot" \
    -resultBundlePath "$dir/Result.xcresult" \
    test > "$dir/xcodebuild.log" 2>&1
  xcrun xcresulttool export attachments --path "$dir/Result.xcresult" \
    --output-path "$dir/shots" --filter "*.png" > "$dir/export.log" 2>&1
  local failures=0
  for shot in 01-home 02-scan-intro 03-manual-entry 04-practice-editor 05-offer 06-align 07-guide 08-expected-solved 09-completed; do
    local png
    png=$(python3 - "$dir/shots/manifest.json" "$dir/shots" "$shot" <<'PY'
import json,sys
for t in json.load(open(sys.argv[1])):
    for a in t.get('attachments', []):
        if a.get('suggestedHumanReadableName', '').startswith(sys.argv[3]):
            print(sys.argv[2] + '/' + a['exportedFileName'])
            raise SystemExit(0)
PY
)
    if [ -z "${png:-}" ]; then echo "MISSING shot $shot on $slot"; failures=1; continue; fi
    local w h
    w=$(sips -g pixelWidth "$png" | tail -1 | awk '{print $2}')
    h=$(sips -g pixelHeight "$png" | tail -1 | awk '{print $2}')
    echo "$slot $shot: ${w}x${h} (expect ${width}x${height})"
    if [ "$w" != "$width" ] || [ "$h" != "$height" ]; then failures=1; continue; fi
    cp "$png" "$dir/$shot-$slot.png"
  done
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  return $failures
}

fail=0
capture "$device_69" "6.9in" 1320 2868 || fail=1
capture "$device_65" "6.5in" 1242 2688 || fail=1
if [ $fail -ne 0 ]; then echo "SCREENSHOT PIPELINE FAILED"; exit 1; fi
echo "SCREENSHOT PIPELINE PASSED"
