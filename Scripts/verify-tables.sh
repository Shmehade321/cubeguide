#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Artifacts
artifact_dir=$(mktemp -d Artifacts/table-check.XXXXXX)
resource_dir=Packages/CubeKit/Sources/CubeSolver3/Resources/Tables
generator_commit=$(python3 -c 'import json; print(json.load(open("Packages/CubeKit/Sources/CubeSolver3/Resources/Tables/manifest.json"))["sourceCommit"])')
# A matching hash is not source provenance. Verify the generating source against its named commit.
if ! git diff --quiet "$generator_commit" -- Packages/CubeKit/Sources/CubeTableTools Packages/CubeKit/Sources/TableGenerator Packages/CubeKit/Sources/CubeSolver3/Coordinates.swift Packages/CubeKit/Sources/CubeSolver3/Cubies.swift Packages/CubeKit/Sources/CubeSolver3/SolverMoves.swift Packages/CubeKit/Sources/CubeSolver3/Tables.swift; then
  echo 'Generator source differs from resource manifest; commit and regenerate resources.' >&2
  exit 1
fi
Scripts/run-logged.sh "$artifact_dir/generation-a.log" swift run -c release --package-path Packages/CubeKit TableGenerator "$artifact_dir/a" "$generator_commit"
Scripts/run-logged.sh "$artifact_dir/generation-b.log" swift run -c release --package-path Packages/CubeKit TableGenerator "$artifact_dir/b" "$generator_commit"
diff -rq "$artifact_dir/a" "$artifact_dir/b"
diff -rq "$artifact_dir/a" "$resource_dir"
Scripts/run-logged.sh "$artifact_dir/oracle-tests.log" python3 -m unittest discover -s Tools/TableValidator -v
Scripts/run-logged.sh "$artifact_dir/validation.log" python3 Tools/TableValidator/validate.py "$resource_dir"
echo "Full table reproduction/validation evidence: $artifact_dir"
