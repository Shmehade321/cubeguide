#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACT_DIR=${ARTIFACT_DIR:-Artifacts/nightly-$(date +%Y%m%d-%H%M%S)}
export TEST_PLAN=Nightly
export CUBE_CORPUS_TIER=nightly
Scripts/test-pr.sh
python3 Tools/MutationChecks/session.py "$ARTIFACT_DIR/session-mutations"
# Required corpus and mutation evidence must exist before claiming nightly qualification.
python3 Scripts/check-qualification.py nightly
