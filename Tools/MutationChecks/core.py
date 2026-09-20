#!/usr/bin/env python3
"""Finite mandatory CubeCore mutations. Run alone: temporarily edits and always restores sources."""
import json
import pathlib
import re
import subprocess

ROOT=pathlib.Path(__file__).resolve().parents[2]
SOURCE=ROOT/'Packages/CubeKit/Sources/CubeCore'
OUT=ROOT/'Artifacts/core-mutations'
OUT.mkdir(parents=True,exist_ok=True)
MUTATIONS=[
 ('invert-face-direction','CubeMoves.swift','let shift = Int(move.turns.rawValue)','let shift = 4 - Int(move.turns.rawValue)','quarterTurnDestinations'),
 ('swap-facelet-destination','CubeMoves.swift','[20,2,51,29]','[20,5,51,29]','quarterTurnDestinations'),
 ('remove-color-count','Validation.swift','guard count == 9 else','guard true else','basicValidation'),
 ('remove-center-check','Validation.swift','guard center == face else','guard true else','basicValidation'),
 ('remove-corner-identity','Validation.swift','identity[$0] == observed[(orientation+$0)%3]','identity[$0] == identity[$0]','impossiblePieces'),
 ('remove-corner-uniqueness','Validation.swift','guard !cornerPermutation.contains(piece) else','guard true else','duplicateCorners'),
 ('remove-edge-uniqueness','Validation.swift','guard !edgePermutation.contains(piece) else','guard true else','impossiblePieces'),
 ('remove-corner-orientation','Validation.swift','guard cornerOrientation % 3 == 0 else','guard true else','cornerTwists'),
 ('remove-edge-orientation','Validation.swift','guard edgeOrientation % 2 == 0 else','guard true else','edgeFlips'),
 ('remove-permutation-parity','Validation.swift','guard parity(cornerPermutation) == parity(edgePermutation) else','guard true else','permutationParity'),
 ('skip-runtime-replay','Replay.swift','guard cube.facelets.applying(moves) == .solved else','guard true else','rejectedReplay'),
 ('remove-solution-length-bound','Replay.swift','guard moves.count <= 30 else','guard true else','rejectedReplay')
]
results=[]
for name,filename,old,new,test in MUTATIONS:
    path=SOURCE/filename
    original=path.read_text()
    if original.count(old)!=1:
        raise SystemExit(f'Mutation target drift: {name}')
    try:
        path.write_text(original.replace(old,new))
        run=subprocess.run(['swift','test','--package-path','Packages/CubeKit','--filter',test],cwd=ROOT,capture_output=True,text=True)
        output=run.stdout+run.stderr
        (OUT/f'{name}.log').write_text(output)
        # Compilation errors or no discovered tests are not a killed behavioral mutation.
        killed=run.returncode!=0 and bool(re.search(r'Test run with [1-9]\d* tests?[^\n]* failed',output))
        row={'mutation':name,'test':test,'killed':killed,'exitCode':run.returncode}
        results.append(row)
        print(json.dumps(row),flush=True)
    finally:
        path.write_text(original)
(OUT/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
if not all(row['killed'] for row in results):
    raise SystemExit('A mutation survived or did not produce a behavioral test failure')
