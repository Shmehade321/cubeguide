#!/usr/bin/env python3
"""Independent replay and complete-outcome accounting for solver measurements."""
import collections
import argparse
import hashlib
import itertools
import json
import math
import pathlib
import re

from generate import SOLVED, turn


def replays_to_solved(state, moves):
    if not isinstance(state, str) or not re.fullmatch('[URFDLB]{54}', state):
        return False
    if not isinstance(moves, list) or len(moves) > 30:
        return False
    for move in moves:
        if not isinstance(move, str) or not re.fullmatch("[URFDLB](2|')?", move):
            return False
        state = turn(state, move[0], {'': 1, '2': 2, "'": 3}[move[1:]])
    return state == SOLVED


def analyze(cases, results, resource_version, expected_count):
    failures = []
    durations = []
    outcomes = collections.Counter()
    count = case_count = 0
    case_ids = set()
    for index, (case, result) in enumerate(itertools.zip_longest(cases, results)):
        if case is not None:
            case_count += 1
            identifier = case.get('id')
            if not isinstance(identifier, str) or not identifier or identifier in case_ids:
                failures.append(f'{index}: missing or duplicate case ID')
            case_ids.add(identifier)
        if result is not None:
            count += 1
            outcomes[result.get('outcome', 'missing')] += 1
            nodes = result.get('visitedNodes')
            if type(nodes) is not int or nodes < 0:
                failures.append(f'{index}: invalid node count')
            elapsed = result.get('elapsedSeconds')
            if type(elapsed) not in (int, float) or not math.isfinite(elapsed) or elapsed < 0:
                failures.append(f'{index}: invalid elapsed time')
            else:
                durations.append(elapsed)
        if case is None or result is None:
            failures.append(f'{index}: missing case or result')
            continue
        if case.get('id') != result.get('id') or case.get('state') != result.get('state'):
            failures.append(f'{index}: case/result identity mismatch')
        if case.get('expectedValid') is True:
            if result.get('outcome') != 'verified':
                failures.append(f'{index}: legal case did not verify')
            if result.get('resourceVersion') != resource_version:
                failures.append(f'{index}: resource version mismatch')
            if not replays_to_solved(case.get('state'), result.get('solution')):
                failures.append(f'{index}: independent replay failed')
        elif case.get('expectedValid') is False:
            if result.get('outcome') != 'invalidInput':
                failures.append(f'{index}: invalid case was not rejected')
        else:
            failures.append(f'{index}: missing expected validity')
    if count != expected_count or case_count != expected_count or expected_count <= 0:
        failures.append('Incomplete or unexpected corpus count')
    durations.sort()
    def percentile(fraction):
        return durations[math.ceil(fraction * len(durations)) - 1] if durations else None
    return {
        'result': 'failed' if failures else 'passed',
        'count': count, 'expectedCount': expected_count, 'caseCount': case_count,
        'outcomes': dict(outcomes), 'timeouts': outcomes['timedOut'],
        'p50Seconds': percentile(.50), 'p95Seconds': percentile(.95),
        'p99Seconds': percentile(.99), 'maximumSeconds': max(durations, default=None),
        'failures': failures,
    }


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus', type=pathlib.Path)
    parser.add_argument('results', type=pathlib.Path)
    parser.add_argument('report', type=pathlib.Path)
    parser.add_argument('--count', type=int, required=True)
    parser.add_argument('--resources', type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.corpus.with_suffix('.manifest.json').read_text())
        corpus_hash = sha256(args.corpus)
        if manifest['sha256'] != corpus_hash or manifest['count'] != args.count:
            raise ValueError('Corpus manifest hash/count mismatch')
        version = sha256(args.resources)
        with args.corpus.open() as cases, args.results.open() as results:
            report = analyze(map(json.loads, cases), map(json.loads, results), version, args.count)
        report.update(corpusSHA256=corpus_hash, resultsSHA256=sha256(args.results),
                      resourceVersion=version, analyzerSHA256=sha256(pathlib.Path(__file__)))
    except (OSError, ValueError, KeyError, TypeError) as error:
        report = {'result': 'failed', 'failures': [str(error)]}
    with args.report.open('x') as output:
        json.dump(report, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps(report, indent=2, allow_nan=False))
    raise SystemExit(0 if report['result'] == 'passed' else 1)
