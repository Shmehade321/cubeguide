#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 Scripts/validate-assets.py
