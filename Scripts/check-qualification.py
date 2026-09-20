#!/usr/bin/env python3
"""Check evidence presence/freshness. This does not independently audit its scientific adequacy."""
import json
import pathlib
import subprocess
import sys

def validate(rows, required, commit, root):
    errors, seen = [], set()
    root = root.resolve()
    for row in rows:
        identifier = row.get('requirementID')
        if identifier in seen or identifier not in required:
            errors.append(f'Duplicate or unknown evidence: {identifier}')
        seen.add(identifier)
        if row.get('commit') != commit or row.get('result') != 'passed':
            errors.append(f'{identifier}: not passed on current source commit')
        paths = row.get('evidencePaths', [])
        if not paths:
            errors.append(f'{identifier}: no evidence artifacts')
        for value in paths:
            path = (root / value).resolve()
            if not path.is_relative_to(root) or not path.is_file() or path.stat().st_size == 0:
                errors.append(f'{identifier}: missing/empty/out-of-root evidence: {value}')
    errors += [f'Missing qualification: {identifier}' for identifier in sorted(required - seen)]
    return errors

if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[1]
    tier = sys.argv[1]
    if tier not in ('nightly','release'):
        sys.exit('Unknown qualification tier')
    evidence = root / 'docs/evidence' / f'{tier}.json'
    if not evidence.is_file():
        sys.exit(f'Blocked: missing {tier} qualification evidence at {evidence}')
    required = ({f'R{i:02}' for i in range(1,21)} if tier == 'release'
                else {'corpus-100000','shallow-46741','coordinate-tables','mutations','images','lifecycle'})
    commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    errors = validate(json.loads(evidence.read_text())['requirements'],required,commit,root)
    if errors:
        sys.exit('\n'.join(errors))
    print('Evidence presence/freshness checks passed; review task and suite scope before qualification claim.')
