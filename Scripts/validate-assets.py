#!/usr/bin/env python3
"""Production asset inventory gate; decoding/listening/bundle checks are additional gates."""
import json
import pathlib
import sys

REQUIRED = {f'{prefix}{number:02}' for prefix, count in [('A',8),('N',30),('E',3)] for number in range(1,count+1)}

def validate(manifest, root, required=REQUIRED):
    errors, seen = [], set()
    root = root.resolve()
    for asset in manifest.get('assets', []):
        identifier = asset.get('id')
        if identifier in seen or identifier not in required:
            errors.append(f'Duplicate or unknown asset ID: {identifier}')
        seen.add(identifier)
        for field in ('path', 'source'):
            value = asset.get(field)
            if not isinstance(value, str) or not value:
                errors.append(f'{identifier}: missing {field}')
                continue
            path = (root / value).resolve()
            if not path.is_relative_to(root) or not path.is_file() or path.stat().st_size == 0:
                errors.append(f'{identifier}: missing, empty or out-of-root {field}: {value}')
    errors += [f'Missing asset: {identifier}' for identifier in sorted(required - seen)]
    return errors

if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[1]
    errors = validate(json.loads((root / 'TestPlans/assets.json').read_text()), root)
    if errors:
        sys.exit('\n'.join(errors))
    print('Asset files and source records present; codec, bundle and human QA require separate evidence.')
