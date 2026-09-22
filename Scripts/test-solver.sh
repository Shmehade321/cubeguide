#!/bin/bash
# Actual Release solver, independent replay, named cases, shallow states and pinned reference.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ARTIFACT_DIR:?Set an output directory for preserved solver evidence}"
solver_out="$ARTIFACT_DIR/solver"
mkdir -p "$solver_out"
python3 - "${CUBE_CORPUS_TIER:-pr}" "${CUBE_CORPUS_SEED:-}" > "$solver_out/selection.txt" <<'PY'
import datetime,json,sys
config=json.load(open('TestPlans/corpora.json'))
selected=config[sys.argv[1]]
seed=int(sys.argv[2],0) if sys.argv[2] else selected.get('seed',int(datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d')))
print(selected['count'],seed)
PY
read -r solver_count solver_seed < "$solver_out/selection.txt"
solver_workers=${CUBE_SOLVER_WORKERS:-$(python3 - <<'PY'
import os
print(min(12, os.cpu_count() or 1))
PY
)}
Scripts/run-logged.sh "$solver_out/build.log" swift build -c release --package-path Packages/CubeKit --product SolverBenchmark
solver_bin_dir=$(swift build -c release --package-path Packages/CubeKit --show-bin-path)
solver_manifest=Packages/CubeKit/Sources/CubeSolver3/Resources/Tables/manifest.json
python3 Tools/Corpus/generate.py "$solver_out/corpus.jsonl" --count "$solver_count" --seed "$solver_seed" > "$solver_out/generation.log"
Scripts/run-logged.sh "$solver_out/benchmark.log" python3 Tools/Corpus/parallel_run.py benchmark --workers "$solver_workers" --input "$solver_out/corpus.jsonl" --output "$solver_out/results.jsonl" -- "$solver_bin_dir/SolverBenchmark"
python3 Tools/Corpus/analyze.py "$solver_out/corpus.jsonl" "$solver_out/results.jsonl" "$solver_out/analysis.json" --count "$solver_count" --resources "$solver_manifest"
python3 Tools/Corpus/generate.py "$solver_out/shallow.jsonl" --shallow > "$solver_out/shallow-generation.log"
Scripts/run-logged.sh "$solver_out/shallow-benchmark.log" python3 Tools/Corpus/parallel_run.py benchmark --workers "$solver_workers" --input "$solver_out/shallow.jsonl" --output "$solver_out/shallow-results.jsonl" -- "$solver_bin_dir/SolverBenchmark"
python3 Tools/Corpus/analyze.py "$solver_out/shallow.jsonl" "$solver_out/shallow-results.jsonl" "$solver_out/shallow-analysis.json" --count 46741 --resources "$solver_manifest"
Scripts/run-logged.sh "$solver_out/named-benchmark.log" "$solver_bin_dir/SolverBenchmark" "$solver_out/named-results.jsonl" < Fixtures/Mathematics/solver-cases.jsonl
python3 Tools/Corpus/analyze.py Fixtures/Mathematics/solver-cases.jsonl "$solver_out/named-results.jsonl" "$solver_out/named-analysis.json" --count 8 --resources "$solver_manifest"
Scripts/test-reference.sh "$solver_out/corpus.jsonl" "$solver_out/reference"
Scripts/test-reference.sh Fixtures/Mathematics/solver-cases.jsonl "$solver_out/named-reference"
