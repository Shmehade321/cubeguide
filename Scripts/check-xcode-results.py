#!/usr/bin/env python3
"""Fail closed when an xcresult is incomplete, failed, skipped or empty."""
import json
import sys

def passed(summary):
    count = summary.get('totalTestCount')
    return (summary.get('result') == 'Passed'
            and type(count) is int and count > 0
            and summary.get('passedTests') == count
            and summary.get('failedTests') == 0
            and summary.get('skippedTests') == 0
            and summary.get('testFailures') == []
            and summary.get('expectedFailures') == 0)

if __name__ == '__main__':
    summary = json.load(open(sys.argv[1]))
    if not passed(summary):
        sys.exit('Xcode test run incomplete, empty, failed or skipped; inspect summary.json')
    print(f"Xcode: {summary['totalTestCount']} executed; 0 skipped; 0 failed")
