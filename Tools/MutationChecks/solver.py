#!/usr/bin/env python3
"""Run alone: seed solver defects, require behavioral failures, always restore source."""
import json
import pathlib
import re
import subprocess

ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE=ROOT/'Packages/CubeKit/Sources/CubeSolver3'
OUT=ROOT/'Artifacts/solver-mutations'
OUT.mkdir(parents=True,exist_ok=True)
MUTATIONS=[
 ('phase-one-equality-pruned','Search.swift','heuristicOne(twist, flip, slice) <= remaining','heuristicOne(twist, flip, slice) < remaining','searchDepthBoundaries'),
 ('phase-two-equality-pruned','Search.swift','heuristicTwo(corners, edges, slice) <= remaining','heuristicTwo(corners, edges, slice) < remaining','searchDepthBoundaries'),
 ('wrong-phase-one-goal','Search.swift','if twist == 0 && flip == 0 && slice == 494','if twist == 0 && flip == 0 && slice == 0','searchDepthBoundaries'),
 ('wrong-phase-two-goal','Search.swift','if corners == 0 && edges == 0 && slice == 0','if corners == 0 && edges == 0 && slice == 1','searchDepthBoundaries'),
 ('retain-phase-boundary-right-history','Search.swift','coordinate.corners, coordinate.edges, coordinate.slice, remaining: depth, previous: -1)','coordinate.corners, coordinate.edges, coordinate.slice, remaining: depth, previous: 1)','phaseBoundaryHistory'),
 ('sparse-cancellation-cadence','Search.swift','visited & 1023 == 0','visited & 2047 == 0','multiPhaseSearch'),
 ('ignore-runtime-cancellation','SolverRuntime.swift','if cancellation.isCancelled','if false','cancelBeforeResources'),
 ('miss-exact-deadline','SolverRuntime.swift','clock.now - started >= limit','clock.now - started > limit','runtimeDeadlines'),
 ('misclassify-wrong-answer','SolverRuntime.swift','case .failure: return finish(.verificationFailure)','case .failure: return finish(.invariantFailure)','runtimeFailures'),
 ('discard-valid-resource-cache','SolverService.swift','let tables = cachedTables','let tables: SolverTables? = nil','serviceCachesValidatedResources'),
 ('expose-completed-stale-answer','SolverService.swift','guard latestRequest == id, !Task.isCancelled, !cancellation.isCancelled else','guard true else','explicitServiceCancellation'),
 ('overlap-replacement-workers','SolverService.swift','let settled = await previous.task.value','let settled = SolverRunResult(outcome: .cancelled, tables: nil, elapsed: .zero, visitedNodes: 0)','serializedService'),
]
results=[]
for name,filename,old,new,test in MUTATIONS:
    path=SOURCE/filename;original=path.read_text()
    if original.count(old)!=1:
        raise SystemExit('Mutation target drift: '+name)
    try:
        path.write_text(original.replace(old,new))
        try:
            run=subprocess.run(['swift','test','--package-path','Packages/CubeKit','--filter',test],cwd=ROOT,capture_output=True,text=True,timeout=120)
            output=run.stdout+run.stderr
            killed=run.returncode!=0 and bool(re.search(r'Test run with [1-9]\d* tests?[^\n]* failed',output))
            code=run.returncode
        except subprocess.TimeoutExpired:
            output='Mutation test process timed out; not counted as a behavioral detection.'
            killed=False;code=None
        (OUT/f'{name}.log').write_text(output)
        row={'mutation':name,'test':test,'killed':killed,'exitCode':code}
        results.append(row);print(json.dumps(row),flush=True)
    finally:
        path.write_text(original)
(OUT/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
if not all(row['killed'] for row in results):
    raise SystemExit('A mutation survived or did not produce a behavioral failure')
