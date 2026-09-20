# T02 — Mathematics and runtime verifier

Status: automated exit passed; physical golden check open. Base: b27c46a. Requirements R04/R06/R07; V01–V03 and replay postconditions.

Plan increments: bounded parsing; all 54 destinations for six quarter turns plus amounts/inverses; 24 orientations and conjugation; piece extraction/legality diagnostics; independently verified plans. Expected output uses fixed literal states/permutations and a separate test-only integer geometry oracle. Physical golden-fixture agreement remains an external qualification check.

Parsing tests catch wrong lengths, illegal labels, unbounded notation, invalid amounts, permissive decode and reversed inverse mapping. Configuration scaffold Face case ordering was established under T01.

## Results

Automated local exit passed. T02 public APIs use namespaces `CubeValidation.validate`, `Replay.verify` (explicit resourceVersion), `Facelets.applying`, and `CubeOrientation`; downstream tasks consume these names. Face/color display mapping remains outside mathematical identity and will be supplied by the scan/editor context. No solver is implemented yet.

Five behavioral red phases were observed before implementations: parsing, explicit move cycles, orientation/regrips, legality and replay. Compressed original transcripts are committed in `t02/`. The first move-test attempt had a tuple type-inference compilation error; corrected before the actual behavioral red run, not counted as TDD evidence.

Final `SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t02-pr Scripts/test-pr.sh` exited 0: 15 infrastructure tests, 27 Swift Testing functions (including parameterized and exhaustive domains), two Xcode tests, zero skipped/failed. Full local `.xcresult` lives in Artifacts/t02-pr; portable app summary and package output are committed.

Covered domains:
- Six clockwise golden permutations on 54 unique labels, all 18 powers/inverses/centers, opposite commutation and adjacent noncommutation, fixed R state and multi-face practice sequence.
- All 24 proper poses, 24×18 conjugations and independent integer-geometry sticker placement; reflected/malformed decoding rejected. Regrip signs agree with the written physical directions.
- All 16 isolated corner twists, 12 isolated edge flips, all 28 corner-pair and 66 edge-pair swaps rejected; balanced orientations and matched parity accepted. Mirrored/impossible/duplicate pieces and count/center ordering covered.
- Independent golden-permutation breadth-first enumeration reproduced [1,18,243,3240,43239], total 46,741 unique states through depth four; every state passed legality. This is not solver execution, which begins in T04.
- Replay accepts only verified solved outcomes, caps plans at 30, preserves immutable original/moves/version, and hashes canonical bytes. Hash fixture independently computed with Python hashlib.
- `python3 Tools/MutationChecks/core.py`: 12/12 behavioral mutations detected; all source restored, then full PR suite rerun. Initial corner-identity mutant was syntactically invalid and correctly NOT counted as detected; corrected the mutant and reran the catalog successfully.
- LLVM executable-line coverage: 100% on all six executable CubeCore source files, 292/292 lines; Face.swift contains enum declarations only. One defensive invalid-cross-product branch in Orientation is unreachable after perpendicular-axis validation; line coverage does not imply branch coverage. Coverage JSON and source hashes are committed.

Ruling: move notation is capped at 256 UTF-8 bytes and 30 tokens before splitting; sufficient for all 30-move plans with ordinary spacing, avoids unbounded allocation. Excessive whitespace is rejected rather than normalized without a bound.

Remaining external evidence: physical golden-fixture agreement and independently reviewed human mathematical conventions have not been performed. These stay open release checks. Finite automated evidence is not a proof over every legal cube. No public release, archive or TestFlight build exists.
