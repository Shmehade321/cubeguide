#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TEST_PLAN=Nightly
export CUBE_CORPUS_TIER=nightly
Scripts/test-pr.sh
# Required corpus and mutation evidence must exist before claiming nightly qualification.
python3 Scripts/check-qualification.py nightly
