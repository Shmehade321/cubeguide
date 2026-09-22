#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ARTIFACT_DIR=${ARTIFACT_DIR:-Artifacts/release-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$ARTIFACT_DIR"
export TEST_PLAN=Release
export CUBE_CORPUS_TIER=release
Scripts/test-pr.sh
Scripts/verify-tables.sh
python3 Tools/MutationChecks/core.py
python3 Tools/MutationChecks/solver.py
python3 Tools/MutationChecks/session.py "$ARTIFACT_DIR/session-mutations"
Scripts/validate-assets.sh
python3 Scripts/check-qualification.py release
