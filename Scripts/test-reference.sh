#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${1:?Supply a JSONL corpus}"
: "${2:?Supply a new evidence directory}"
reference_corpus=$1
reference_out=$2
reference_workers=${CUBE_SOLVER_WORKERS:-$(python3 - <<'PY'
import os
print(min(12, os.cpu_count() or 1))
PY
)}
mkdir "$reference_out"
reference_java=${JAVA_HOME:-$(/usr/libexec/java_home -v 11)}
"$reference_java/bin/java" -version > "$reference_out/java.txt" 2>&1
python3 - "$reference_corpus" "$reference_out/input.txt" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path('Tools/ReferenceSolver')
manifest=json.loads((root/'source-hashes.json').read_text())
for name,expected in manifest['files'].items():
    if hashlib.sha256((root/name).read_bytes()).hexdigest()!=expected:
        raise SystemExit('Pinned reference source changed: '+name)
with open(sys.argv[2],'x') as output:
    for line in open(sys.argv[1]):
        output.write(json.loads(line)['state']+'\n')
PY
mkdir "$reference_out/classes"
"$reference_java/bin/javac" -d "$reference_out/classes" Tools/ReferenceSolver/upstream/src/*.java Tools/ReferenceSolver/adapter/ReferenceRunner.java
Scripts/run-logged.sh "$reference_out/runner.log" python3 Tools/Corpus/parallel_run.py stdio --workers "$reference_workers" --input "$reference_out/input.txt" --output "$reference_out/results.tsv" -- "$reference_java/bin/java" -cp "$reference_out/classes" ReferenceRunner
python3 Tools/ReferenceSolver/compare.py "$reference_corpus" "$reference_out/results.tsv" "$reference_out/analysis.json"
