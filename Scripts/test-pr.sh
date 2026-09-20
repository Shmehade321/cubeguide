#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACT_DIR=${ARTIFACT_DIR:-Artifacts/pr-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$ARTIFACT_DIR"
xcodebuild -version > "$ARTIFACT_DIR/toolchain.txt"
swift --version >> "$ARTIFACT_DIR/toolchain.txt"
git rev-parse HEAD > "$ARTIFACT_DIR/commit.txt"
Scripts/run-logged.sh "$ARTIFACT_DIR/infrastructure.log" python3 -m unittest discover -s Tests/Infrastructure -v
Scripts/run-logged.sh "$ARTIFACT_DIR/table-oracle-tests.log" python3 -m unittest discover -s Tools/TableValidator -v
Scripts/test-package.sh
# Require an explicit installed simulator; never substitute a different OS silently.
: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to an installed qualification simulator}"
xcrun simctl list devices available -j > "$ARTIFACT_DIR/simulators.json"
python3 - "$SIMULATOR_UDID" "$ARTIFACT_DIR/simulators.json" <<'PY'
import json,sys
matches = [(runtime,device) for runtime,devices in json.load(open(sys.argv[2]))['devices'].items() for device in devices if device['udid'] == sys.argv[1] and device['isAvailable']]
if len(matches) != 1:
    sys.exit('Required simulator unavailable; no fallback is permitted')
print('Selected:', matches[0])
PY
Scripts/run-logged.sh "$ARTIFACT_DIR/xcode.log" xcodebuild test -project cubeguide.xcodeproj -scheme cubeguide -testPlan "${TEST_PLAN:-PR}" -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" -derivedDataPath DerivedData -resultBundlePath "$ARTIFACT_DIR/tests.xcresult" CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path "$ARTIFACT_DIR/tests.xcresult" > "$ARTIFACT_DIR/summary.json"
python3 Scripts/check-xcode-results.py "$ARTIFACT_DIR/summary.json"
