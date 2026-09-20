#!/usr/bin/env python3
"""Test-only reference agreement by validity and independent replay, not move text."""
import argparse
import itertools
import json
import pathlib
import re
import sys

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'Corpus'))
from analyze import replays_to_solved, sha256


def compare(cases, lines):
    failures=[];count=0
    for index,(case,line) in enumerate(itertools.zip_longest(cases,lines)):
        if line is not None:
            count+=1
        if case is None or line is None:
            failures.append(f'{index}: missing case or reference result')
            continue
        fields=line.rstrip('\r\n').split('\t')
        if len(fields)!=2 or fields[0]!=case['state']:
            failures.append(f'{index}: reference state mismatch')
            continue
        answer=fields[1].strip()
        if case['expectedValid']:
            if not replays_to_solved(case['state'],answer.split()):
                failures.append(f'{index}: reference did not independently verify: {answer}')
        elif not re.fullmatch('Error [1-6]',answer):
            failures.append(f'{index}: reference did not report input invalidity: {answer}')
    if not count:
        failures.append('Empty reference corpus')
    return {'result':'failed' if failures else 'passed','count':count,'failures':failures}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus',type=pathlib.Path)
    parser.add_argument('reference',type=pathlib.Path)
    parser.add_argument('report',type=pathlib.Path)
    args=parser.parse_args()
    with args.corpus.open() as cases,args.reference.open() as lines:
        report=compare(map(json.loads,cases),lines)
    report.update(corpusSHA256=sha256(args.corpus),referenceSHA256=sha256(args.reference),
                  upstreamCommit='4d183b9eff8119cac72bc50ef35a7d8990740e06',
                  comparatorSHA256=sha256(pathlib.Path(__file__)))
    with args.report.open('x') as output:
        json.dump(report,output,indent=2);output.write('\n')
    print(json.dumps(report,indent=2))
    raise SystemExit(0 if report['result']=='passed' else 1)
