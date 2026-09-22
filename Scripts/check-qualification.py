#!/usr/bin/env python3
"""Validate typed, checksummed qualification evidence for the exact candidate commit."""
import hashlib
import json
import pathlib
import subprocess
import sys
from datetime import datetime

RELEASE_KINDS = {
    'R01': {'test-summary'}, 'R02': {'camera-report'}, 'R03': {'camera-report'},
    'R04': {'test-summary'}, 'R05': {'test-summary'}, 'R06': {'benchmark-report'},
    'R07': {'test-summary'}, 'R08': {'device-report'}, 'R09': {'mutation-report'},
    'R10': {'device-report'}, 'R11': {'test-summary'}, 'R12': {'accessibility-report'},
    'R13': {'benchmark-report'}, 'R14': {'privacy-report'}, 'R15': {'accessibility-report'},
    'R16': {'visual-report'}, 'R17': {'media-report'}, 'R18': {'lifecycle-report'},
    'R19': {'archive-report'}, 'R20': {'archive-report'},
}
NIGHTLY_KINDS = {
    'corpus-100000': {'benchmark-report'}, 'shallow-46741': {'test-summary'},
    'coordinate-tables': {'table-report'}, 'mutations': {'mutation-report'},
    'images': {'camera-report'}, 'lifecycle': {'lifecycle-report'},
}
DEVICE_KINDS = {'camera-report', 'device-report', 'accessibility-report', 'lifecycle-report'}
ALL_KINDS = set().union(*RELEASE_KINDS.values(), *NIGHTLY_KINDS.values())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_artifact(artifact, identifier, commit, root, allowed_kinds=ALL_KINDS):
    errors = []
    root = root.resolve()
    if not isinstance(artifact, dict):
        return [f'{identifier}: evidence entry is not an object']
    kind, value, expected_hash = artifact.get('kind'), artifact.get('path'), artifact.get('sha256')
    if kind not in allowed_kinds:
        errors.append(f'{identifier}: unknown evidence kind {kind!r}')
    if not isinstance(value, str) or not value:
        return errors + [f'{identifier}: evidence path is missing']
    path = (root / value).resolve()
    if not path.is_relative_to(root) or not path.is_file() or path.stat().st_size == 0:
        return errors + [f'{identifier}: missing/empty/out-of-root evidence: {value}']
    if path.suffix != '.json':
        return errors + [f'{identifier}: qualifying evidence must be structured JSON: {value}']
    if expected_hash != digest(path):
        errors.append(f'{identifier}: checksum mismatch for {value}')
    try:
        payload = json.loads(path.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        return errors + [f'{identifier}: invalid JSON evidence {value}: {error}']
    if payload.get('schemaVersion') != 1 or payload.get('kind') != kind:
        errors.append(f'{identifier}: artifact schema/kind mismatch in {value}')
    if payload.get('commit') != commit or payload.get('result') != 'passed':
        errors.append(f'{identifier}: artifact is not passed on current commit: {value}')
    if not payload.get('generatedBy') or not payload.get('executedAt'):
        errors.append(f'{identifier}: artifact lacks producer/time metadata: {value}')
    else:
        try:
            executed_at = datetime.fromisoformat(payload['executedAt'].replace('Z', '+00:00'))
            if executed_at.tzinfo is None:
                raise ValueError('timezone is required')
        except (AttributeError, TypeError, ValueError):
            errors.append(f'{identifier}: artifact has invalid executedAt timestamp: {value}')
    if kind in DEVICE_KINDS and not payload.get('device'):
        errors.append(f'{identifier}: {kind} lacks physical device identity')
    elif kind in DEVICE_KINDS:
        device = payload['device']
        if not isinstance(device, dict) or device.get('physical') is not True or not all(
            device.get(field) for field in ('model', 'osVersion', 'build')
        ):
            errors.append(f'{identifier}: {kind} device identity is incomplete or not physical')
    if kind == 'media-report' and not payload.get('listeningSignoff'):
        errors.append(f'{identifier}: media report lacks listening sign-off')
    if kind == 'archive-report' and not payload.get('archiveSHA256'):
        errors.append(f'{identifier}: archive report lacks archive checksum')
    return errors


def validate(rows, required, commit, root, tier='release'):
    errors, seen = [], set()
    root = root.resolve()
    kind_map = RELEASE_KINDS if tier == 'release' else NIGHTLY_KINDS
    for row in rows:
        identifier = row.get('requirementID') if isinstance(row, dict) else None
        if identifier in seen or identifier not in required:
            errors.append(f'Duplicate or unknown evidence: {identifier}')
        seen.add(identifier)
        if not isinstance(row, dict) or row.get('commit') != commit or row.get('result') != 'passed':
            errors.append(f'{identifier}: ledger row is not passed on current source commit')
            continue
        artifacts = row.get('evidence', [])
        if not artifacts:
            errors.append(f'{identifier}: no typed evidence artifacts')
            continue
        required_kinds = kind_map.get(identifier, set())
        row_kinds = {entry.get('kind') for entry in artifacts if isinstance(entry, dict)}
        if not (row_kinds & required_kinds):
            errors.append(f'{identifier}: missing required evidence kind {sorted(required_kinds)}')
        for artifact in artifacts:
            errors.extend(validate_artifact(artifact, identifier, commit, root))
    errors += [f'Missing qualification: {identifier}' for identifier in sorted(required - seen)]
    return errors


if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[1]
    if len(sys.argv) != 2 or sys.argv[1] not in ('nightly', 'release'):
        sys.exit('Usage: check-qualification.py nightly|release')
    tier = sys.argv[1]
    evidence = root / 'docs/evidence' / f'{tier}.json'
    if not evidence.is_file():
        sys.exit(f'Blocked: missing {tier} qualification evidence at {evidence}')
    required = ({f'R{i:02}' for i in range(1, 21)} if tier == 'release'
                else set(NIGHTLY_KINDS))
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip():
        sys.exit('Qualification requires a clean committed source tree')
    document = json.loads(evidence.read_text())
    if document.get('schemaVersion') != 1 or document.get('tier') != tier:
        sys.exit('Evidence ledger schema or tier is invalid')
    errors = validate(document.get('requirements', []), required, commit, root, tier)
    if errors:
        sys.exit('\n'.join(errors))
    print('Typed evidence checks passed for the exact candidate commit.')
