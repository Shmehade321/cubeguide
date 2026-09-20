#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TEST_PLAN=Release
export CUBE_CORPUS_TIER=release
Scripts/test-pr.sh
Scripts/validate-assets.sh
python3 Scripts/check-qualification.py release
