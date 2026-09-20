#!/bin/bash
set -euo pipefail
if [[ $# -lt 2 ]]; then
  echo 'Usage: run-logged.sh LOG COMMAND [ARG...]' >&2
  exit 64
fi
log=$1
shift
mkdir -p "$(dirname "$log")"
"$@" 2>&1 | tee "$log"
