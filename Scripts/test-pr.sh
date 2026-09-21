#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACT_DIR=${ARTIFACT_DIR:-Artifacts/pr-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$ARTIFACT_DIR"
xcodebuild -version > "$ARTIFACT_DIR/toolchain.txt"
swift --version >> "$ARTIFACT_DIR/toolchain.txt"
git rev-parse HEAD > "$ARTIFACT_DIR/commit.txt"
python3 - "$ARTIFACT_DIR/source-state.json" <<'PY_SOURCES'
import hashlib,json,pathlib,subprocess,sys
paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z']).decode().split('\0')
files={name:hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() for name in sorted(set(paths)) if name and pathlib.Path(name).is_file()}
json.dump({'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
           'status':subprocess.check_output(['git','status','--porcelain'],text=True),'files':files},open(sys.argv[1],'w'),indent=2)
PY_SOURCES
Scripts/run-logged.sh "$ARTIFACT_DIR/infrastructure.log" python3 -m unittest discover -s Tests/Infrastructure -v
Scripts/run-logged.sh "$ARTIFACT_DIR/table-oracle-tests.log" python3 -m unittest discover -s Tools/TableValidator -v
Scripts/run-logged.sh "$ARTIFACT_DIR/corpus-tests.log" python3 -m unittest discover -s Tools/Corpus -v
Scripts/run-logged.sh "$ARTIFACT_DIR/reference-tests.log" python3 -m unittest discover -s Tools/ReferenceSolver -v
Scripts/test-package.sh
Scripts/test-storage-crashes.sh
Scripts/test-solver.sh
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
