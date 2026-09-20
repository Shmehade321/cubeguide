#!/usr/bin/env python3
"""Require a nonempty, successful Swift Testing run without skipped tests."""
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
counts = re.findall(r'✔ Test run with (\d+) tests?\b[^\n]* passed', text)
if not counts or any(int(count) == 0 for count in counts):
    sys.exit('No nonempty successful Swift Testing summary found')
if re.search(r'\bskipped\b|✘', text, re.IGNORECASE):
    sys.exit('Skipped or failed tests present')
print(f'Swift Testing: {sum(map(int, counts))} executed; 0 skipped; 0 failed')
