#!/bin/bash
# Host process-kill qualification; never substitutes for physical iOS tests.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ARTIFACT_DIR:?Set an output directory for preserved storage evidence}"
storage_out="$ARTIFACT_DIR/storage-crashes"
mkdir -p "$ARTIFACT_DIR"
Scripts/run-logged.sh "$ARTIFACT_DIR/storage-process-tests.log" python3 -m unittest discover -s Tools/StorageCrash -v
Scripts/run-logged.sh "$ARTIFACT_DIR/storage-probe-build.log" swift build --package-path Packages/CubeKit --product SessionStoreCrashProbe
storage_bin_dir=$(swift build --package-path Packages/CubeKit --show-bin-path)
Scripts/run-logged.sh "$ARTIFACT_DIR/storage-crashes.log" python3 Tools/StorageCrash/qualify.py "$storage_bin_dir/SessionStoreCrashProbe" "$storage_out"
