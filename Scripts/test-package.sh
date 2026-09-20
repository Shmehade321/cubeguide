#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir=${ARTIFACT_DIR:-Artifacts/package-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$artifact_dir"
Scripts/run-logged.sh "$artifact_dir/swift.log" swift test --package-path Packages/CubeKit --enable-code-coverage "$@"
python3 Scripts/check-swift-results.py "$artifact_dir/swift.log"
