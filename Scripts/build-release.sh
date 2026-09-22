#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/validate-assets.sh
Scripts/verify-tables.sh
python3 Scripts/check-qualification.py release
: "${DEVELOPMENT_TEAM:?Owner must provide the signing team}"
artifact_dir=${ARTIFACT_DIR:-Artifacts/archive-$(date +%Y%m%d-%H%M%S)}
Scripts/run-logged.sh "$artifact_dir/archive.log" xcodebuild archive -project cubeguide.xcodeproj -scheme cubeguide -configuration Release -destination 'generic/platform=iOS' -archivePath "$artifact_dir/cubeguide.xcarchive" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
