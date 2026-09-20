# T04 — Real search and qualification

Status: automated implementation exit passed; physical qualification open. Base: 3856905. R06/R13; V05/V06. Previous goal turn made verified progress: T01–T03 code/resources committed, working tree clean at continuation.

Required work: complete bounded IDA* phases (12/18), admissible pruning, reset move history at phase boundary, typed resource/cancellation/timeout/invariant outcomes, independent replay, serialized off-main orchestration and stale revision handling, exhaustive shallow and seeded PR corpus, pinned differential reference, device qualification where available.

No search performance or phone qualification claim is made before execution. Default/extended deadlines are 10/60 seconds, not unsolvability criteria. CPU work must remain outside the main actor.

## Implemented search and service

Original table-driven IDA* searches phase one through depth 12 and phase two through 18. It accepts goals at depth zero, prunes only above the remaining depth, omits consecutive same-face turns within a phase, and resets history between phases. The literal R boundary case requires R followed by R2 in the stable search order. Additional fixtures exercise exhausted heuristic bounds before succeeding at the next depth: `R U R U2` has phase-one h=3/distance=4; `R2 F2 U2 R2 F2` has phase-two h=4/distance=5.

The runtime uses an injected monotonic clock and cancellation token; typed outcomes separate resource failures, timeouts, cancellation, wrong answers and exhausted invariants. Cancellation is checked at entry, load operations, phase boundaries, at most 1,024 visited nodes, and around independent replay. Only Replay constructs a VerifiedPlan. An actor serializes worker orchestration, explicitly awaits replacement cancellation, caches only validated resources and rejects stale completed answers. Actual search runs off the main actor.

The app dependency container now owns the real service and links CubeSolver3/resources. Its integration acceptance test solves the independent literal R snapshot inside the simulator app. This configuration/trivial dependency wiring uses the plan's predeclared integration acceptance rule; it is not claimed as a separate behavioral RED cycle. The app's user interface is still the starter screen; the manual product flow is T06.

## TDD and finite evidence

Behavioral RED was observed for search, depth bounds, runtime outcomes, service serialization/cancellation, corpus generation, result accounting and reference comparison before each implementation. Compressed transcripts are retained in `t04/`. Later tests extend coverage of already-implemented load deadlines, resource caching, delayed stale-result delivery and exhausted heuristic bounds; these are not misreported as new RED implementations.

The release benchmark produces raw per-case durations, resource identity, move sequence and visited-node counts. A separate Python analyzer matches all inputs/results, validates the frozen corpus manifest, retains outliers/timeouts, and independently replays every answer using geometry fixtures. It rejects wrong states/sequences, omitted/duplicate IDs, wrong resource versions and invalid measurements. The test-only pinned Java reference is a separate process; depth/probe failures never count as input invalidity.

All 12 seeded solver mutations and all 12 existing CubeCore mutations produced behavioral test failures; compilation errors/timeouts are not counted as detections. Sources were restored before final regression. The table validator separately detects a corrupted entry in each of the ten tables. No skipped check is treated as a pass.

Final integrated regression and table regeneration passed. Hardware inventory currently contains only simulated iPhones. Physical golden fixtures, 1,000-state cold/warm qualification, 250 ms cancellation and whole-app memory measurements remain open. Nightly 100,000 and release million-state tiers are configured but not claimed as executed. Remote CI cannot run without a Git remote; no archive, TestFlight or public release exists.

## Final local regression

`SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t04-final-pr Scripts/test-pr.sh` exited 0: 64 Swift package tests (27 Core, 33 solver, four generator), 34 Python tests (15 infrastructure, six table oracle, ten corpus/accounting, three reference), and three Xcode app/UI tests. Zero failed/skipped/expected-failure tests. Xcode emitted the existing no-AppIntents-dependency metadata warning; no runtime warnings were reported. Source file hashes captured before testing match the implementation at this commit; only evidence/documentation was added after the run.

- PR: 10,000 unique legal states, all independently replayed; 5,000 direct + 1,250 at each scramble length 20/40/80/200. No timeout. Warm desktop Release p95 0.042480 s, p99 0.090275 s, maximum 0.626600 s. These are runner measurements, not phone qualification.
- Shallow: every one of 46,741 independently enumerated states solved and independently replayed.
- Named: solved, literal R, superflip and balanced corner twists verified; single twist, single flip, unmatched edge swap and wrong color count rejected.
- Pinned reference: all 10,000 PR and eight named cases agreed on expected validity; every accepted reference answer independently replayed to solved. Different solution strings are permitted.
- `Scripts/verify-tables.sh` exited 0: two identical clean generations matched packaged resources; every transition and distance was independently validated. Full local evidence: `Artifacts/table-check.uH6ENz/`.

Portable summaries, corpus manifests, raw compressed PR inputs/results/reference answers, shallow results, red transcripts and mutation reports are committed under `t04/`. The full `.xcresult` remains in `Artifacts/t04-final-pr/`; reproduction commands and source identity are recorded. T04's physical performance exit remains open; the plan explicitly permits independent T05/UI work while hardware is unavailable. No claim of complete product qualification or public shipment is made.
