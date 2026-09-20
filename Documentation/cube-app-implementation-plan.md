# CubeGuide — Implementation Contract and Delivery Plan

> Historical revision 2 planning/review baseline. Implementation status below describes the time of that review; current execution status is tracked in [the evidence ledger](../docs/evidence/progress.md).

Revision 2 · 20 September 2026

**Goal:** Deliver the complete offline 3×3 iPhone product defined by [the specification](cube-app-specification.md), with the evidence required by [the verification plan](cube-app-verification-plan.md).

**Architecture:** A pure Swift package owns mathematics, search, scanning calculations and session transitions. SwiftUI/AVFoundation/RealityKit adapters own hardware and presentation. The solver's output is independently replayed before guidance.

**Execution:** Implement tasks sequentially, splitting each task into the red/green increments listed below. This document requests no agent delegation. Each task requires actual implementation, regression tests, integration and a reviewed commit; a checklist tick or generated file alone is not a deliverable.

**Status:** No product implementation or asset generation has been performed. Paths below are target repository paths, not claims that files exist. Integrate into the user's existing Xcode project; record a one-time name/path mapping if it differs from CubeGuide. Do not create a second app or overwrite existing project settings without inspecting them.

## Global constraints

- iOS 18.0+, iPhone, Swift 6 language mode; offline runtime with no AI, cloud service, account, purchase flow or analytics SDK.
- All R01–R20 requirements apply. Specification governs behavior; this plan governs implementation sequence; verification plan governs evidence. Resolve contradictions in a versioned document change before dependent code.
- Preserve user files and existing signing identity. Work in the actual repository; no guessed paths, credentials or store identity.
- New behavior and fixes require failing behavioral tests first. Repository config/generated-art templates use predeclared acceptance checks; they do not require meaningless tests that merely compare a file to itself.
- Every delivered solution passes independent runtime replay. Color review, offline recovery, sound, graphics and accessibility are required product work.
- Critical/high correctness defects and missing mandatory evidence block release. Thresholds cannot be weakened automatically to make CI green.

## Review focus

1. A valid-but-wrong scan can pass the solver: test real ground truth and preserve user review (T06/T09).
2. A physical turn can happen before its acknowledgement is durably saved: test crash/write failure and ambiguous resume (T05/T08).
3. Rendering, narration and regrips can disagree while math tests pass: verify the same action identity across all three and perform physical listening trials (T07/T08/T10).
4. A pruning table or optimized search can discard valid paths: independently derive table distances and test full phase bounds (T03/T04).
5. “Offline” can fail only on clean install or packaged resources: test the archived app, bundled audio and resources on disconnected physical devices (T11/T12).

## 1. Target repository structure

```text
CubeGuide.xcodeproj                    # existing app project, mapped if named differently
CubeGuide/App/CubeGuideApp.swift
CubeGuide/App/AppDependencies.swift
CubeGuide/Features/Home/
CubeGuide/Features/Scan/
CubeGuide/Features/Editor/
CubeGuide/Features/Guide/
CubeGuide/Features/Settings/
CubeGuide/Adapters/CameraCapture.swift
CubeGuide/Adapters/SessionStore.swift
CubeGuide/Adapters/AudioCoordinator.swift
CubeGuide/Adapters/HapticFeedback.swift
CubeGuide/Presentation/CubeScene.swift
CubeGuide/Presentation/MoveAnimator.swift
CubeGuide/Resources/Assets.xcassets
CubeGuide/Resources/Audio/
CubeGuide/Resources/Content/phrases.json
CubeGuide/Resources/Content/help.md
CubeGuide/Resources/Content/privacy.md
CubeGuide/Resources/Content/licenses.txt
CubeGuide/Resources/PrivacyInfo.xcprivacy # entries based on audited API/dependency use
Packages/CubeKit/Package.swift
Packages/CubeKit/Sources/CubeCore/{Facelets,Move,Orientation,Validation,Replay}.swift
Packages/CubeKit/Sources/CubeSolver3/{Cubies,Coordinates,Tables,Search,SolverService}.swift
Packages/CubeKit/Sources/CubeSolver3/Resources/Tables/
Packages/CubeKit/Sources/CubeScan/{FaceGeometry,ColorSamples,Classification,ScanDraft}.swift
Packages/CubeKit/Sources/CubeSession/{Session,Action,Reducer,GuidePlanner}.swift
Packages/CubeKit/Tests/{CubeCoreTests,CubeSolver3Tests,CubeScanTests,CubeSessionTests}/
CubeGuideTests/{PersistenceTests,AudioTests,SceneTests,PerformanceTests}/
CubeGuideUITests/{ManualFlowTests,ScanFlowTests,GuideFlowTests,AccessibilityTests}/
Tools/TableGenerator/
Tools/ReferenceSolver/                 # pinned test-only upstream source/invocation + notices
Tools/AssetValidation/
Fixtures/{Mathematics,Scans,CorpusManifests}/
TestPlans/{PR,Nightly,Release}.xctestplan
Scripts/{test-pr,test-nightly,test-release,validate-assets,build-release}.sh
docs/{specification,verification-plan,implementation-plan,architecture,release-runbook}.md
docs/evidence/                        # manifests/reports; large result bundles attached in CI
```

Braced groups are individual files/directories, not literal filenames. Keep the package free from UI/hardware imports except explicitly platform-bound test adapters. Import Foundation where required; do not invoke AVFoundation/RealityKit from pure mathematics.

## 2. Shared data contracts

Define these semantics before adding adapters. Swift spelling may be adjusted to existing naming conventions once, with all consumers/tests changed together; do not let each feature invent a different state model.

- `Face`: six cases in U,R,F,D,L,B order.
- `Move`: face and `QuarterTurns` in {1,2,3}; 3 denotes inverse. `inverse` maps 1↔3 and 2↔2.
- `Facelets`: exactly 54 canonical face labels, immutable. Parsing uses a bounded input and typed errors; public solver entry receives `LegalCube` only.
- `LegalCube`: validated facelets plus immutable center-color/display mapping held outside the mathematical identity. Mathematical equality excludes sampled RGB values.
- `CubeOrientation`: one of 24 proper rotations mapping canonical faces to physical/view directions. Does not mutate `Facelets`.
- `VerifiedPlan`: original state, canonical move array of length 0…30, original-state hash, resource version and verification result. Only `Replay.verify` constructs it.
- `SolveOutcome`: `.verified(VerifiedPlan)`, `.cancelled`, `.timedOut`, `.invalidInput(issues)`, `.resourceFailure(reason)`, `.verificationFailure`, `.invariantFailure`. Cancellation/timeout never means the cube is impossible.
- `GuideAction`: unique `(sessionRevision, moveIndex, actionIndex)` plus `.regrip(operation, fromPose, toPose)` or `.turn(canonicalMove, before, after, pose)`. Renderer/audio/captions consume the same action.
- `Session`: original state, verified plan, durable move index, durable pose, pending action identity, active preview status and completion kind. Step indices use half-open ranges and are bounded on decode.
- `ScanDraft`: slot→nine robust color measurements, labels/manual overrides, center assignment, crop metadata, pose and revision. No durable images.
- `SessionEvent`: start/review/acceptScan/solveResult/preview/play/pause/acknowledge/persisted/persistFailed/background/resumeChoice/recover/confirmCompletion/delete. Reducer returns state plus side-effect commands; persistence acknowledgement is a separate event.

Durable action preparation: save the pending action identity and its before-state before enabling its demonstration. After physical acknowledgement, save the new pose/index before exposing a following action. If either save fails, keep the last valid file, stop progress and offer retry or rescan. A relaunch reconstructs the pending action deterministically from its saved identity; it does not assume that an unsaved acknowledgement never happened physically.

Required workflow states and permitted transitions (all unlisted state/event pairs produce a typed rejected action or explicit no-op, never a hidden transition):

| State | Permitted transitions |
|---|---|
| home | startScan→scanning; startManual→editing; resume→resumeCheck; practice→editing in isolated practice context |
| scanning | capture→faceReview; cancel→home with durable draft; interruption→pausedCapture |
| faceReview | accept→scanning or editing after six faces; retake→scanning; edit/rotate→faceReview; cancel→home |
| pausedCapture | retry→scanning; manual→editing; exit→home |
| editing | edit/rotate→editing with new revision; validate→invalid/offer/alreadySolved; cancel→home |
| invalid | edit→editing; rescan→scanning; exit→home |
| alreadySolved | confirm→completed with entered/scanned origin; new→home |
| offer | consentYes→solving; consentNo→home; edit→editing |
| solving | matchingVerifiedResult→preparingAction; timeout/error→solveError; cancel→offer; staleResult→no-op |
| solveError | retry→solving; edit→editing; exit→home |
| preparingAction | persisted→guide; failed→storageError; cancel/background→resumeCheck |
| guide | play/pause/replay→guide preview substate; acknowledge→savingAcknowledgement; mismatch→recovery; background/exit→resumeCheck |
| savingAcknowledgement | matchingPersisted→preparingAction or expectedSolved after last turn; failed→storageError; duplicate/stale event→no-op |
| storageError | retrySave→prior save state only after explicit before/after physical check; rescan→recovery; exit→home |
| resumeCheck | confirmedBefore→guide; confirmedAfter→savingAcknowledgement for that one pending action; uncertain→recovery; exit→home |
| recovery | newScan→scanning in new revision; manual→editing in new revision; cancel→resumeCheck preserving old session |
| expectedSolved | userConfirms→completed(userConfirmed); checkCamera→scanning in verification context; mismatch→recovery |
| completed | new→home; checkCamera→scanning in verification context; exit→home |

Global delete cancels producers, increments the session/storage generation, serializes behind in-flight writes, removes files and returns home only after deletion succeeds; on deletion failure show the error without claiming erasure. On background/interruption: scanning/faceReview→pausedCapture (retain accepted measurements, discard unaccepted image); solving→offer after cancellation; guide/preparingAction→resumeCheck; editing/invalid/offer/completed retain their state. An outstanding acknowledgement write settles under its original revision, then enters resumeCheck unless it durably completed the final move, in which case resume asks for solved confirmation. No resumeCheck is constructed without a verified plan and pending/next action. Help/settings navigation preserves the previous workflow state but pauses camera/audio. A completed six-face verification returns to editing for review, then to completed(scanVerified) if solved, offer if valid-scrambled, or invalid; it does not overwrite the old session until the user accepts replacement.

Minimum callable package interfaces for implementation/test planning:

```swift
func validate(_ facelets: Facelets) -> Result<LegalCube, ValidationIssues>
func applying(_ moves: [Move], to state: Facelets) -> Facelets
func verify(_ moves: [Move], for cube: LegalCube) -> Result<VerifiedPlan, VerificationError>
func plannedActions(for move: Move, at pose: CubeOrientation,
                    state: Facelets, id: ActionID) -> [GuideAction]
func reduce(_ session: Session, event: SessionEvent) -> Transition
```

Constructors enforce bounds; never force-unwrap camera/session input. Use an injected monotonic clock and cancellation token for the search; solver tests do not wait real seconds to simulate deadlines. Execute one mutable search job at a time in the app, with immutable verified tables shareable across jobs. Actor isolation serializes orchestration; CPU search must run off the main actor rather than accidentally blocking it through an inherited task context.

## 3. Geometry, moves and orientation contract

World axes: +X right, +Y up, +Z toward the viewer. Each sticker row/column is 0…2. Its cubie coordinate is `normal + (column−1)*right + (1−row)*up`.

| Face | Outward normal | Screen-right basis | Screen-up basis |
|---|---|---|---|
| U | +Y | +X | −Z |
| R | +X | −Z | +Y |
| F | +Z | +X | +Y |
| D | −Y | +X | +Z |
| L | −X | +Z | +Y |
| B | −Z | −X | +Y |

A clockwise face turn is a −90° right-hand rotation about its outward normal, affecting stickers whose cubie coordinate lies in that outer layer. Rotate sticker normals too. Derive independently reviewed golden facelet permutations and a separate test oracle; do not generate expected results by invoking the production function under test.

Whole-cube regrip operations use fixed viewer axes and rotate every cubie and sticker normal:

| Operation | Rotation | Narration |
|---|---|---|
| yawLeft | −90° about +Y | N04; current front moves to the viewer's left |
| yawRight | +90° about +Y | N05; current front moves right |
| topToward | +90° about +X | N06; current top becomes front |
| bottomToward | −90° about +X | N07; current bottom becomes front |
| rollClockwise | −90° about +Z | N08 |
| rollCounterclockwise | +90° about +Z | N09 |

For a solver move, breadth-first search the 24-orientation graph from the confirmed pose to any pose where its face is front. Neighbor order is the six table rows above; the first goal in that stable traversal wins. Emit each regrip as an acknowledged action, then a front turn with the original clockwise/inverse/half amount. Use current front/top/right labels after every regrip. Update pose only on durable regrip acknowledgement; update logical cube and move index only on durable turn acknowledgement. Pose never affects mathematical legality.

The scan planner uses the same orientation graph but targets exact front/top constraints from the specification for each F,R,B,L,U,D capture. Do not guess which edge is “top” from sticker colors. A center image by itself contains no orientation information.

## 4. Original solver and table contract

Use these cubie position orders, also used as solved piece identities:

- Corners: URF, UFL, ULB, UBR, DFR, DLF, DBL, DRB. Ordered face triples: (U,R,F), (U,F,L), (U,L,B), (U,B,R), (D,F,R), (D,L,F), (D,B,L), (D,R,B).
- Edges: UR, UF, UL, UB, DR, DF, DL, DB, FR, FL, BL, BR, with each ordered pair as written.
- Corner orientation is the index 0…2 of the piece's U/D sticker in the position's ordered triple; remaining colors must match a cyclic ordering, not a mirrored ordering. Edge orientation is 0 for matching the ordered identity pair and 1 for its reversal.

Permutation coordinates use lexicographic Lehmer ranking with solved rank zero. Corner orientation ranks the first seven digits in base 3; derive the eighth from modulo-three sum. Edge orientation ranks the first eleven digits in base 2; derive the twelfth from parity. UD-slice occupancy ranks the ascending four occupied position indices in lexicographic combination order from 0 to 494; the solved {8,9,10,11} goal is 494. Never assume all goal coordinates are zero.

Phase-one moves are the 18 face turns in U,R,F,D,L,B order, with amounts 1,2,3. Phase-two moves, in order, are U,U2,U',D,D2,D',R2,F2,L2,B2. In phase two, the eight non-slice edges occupy positions 0…7 and slice edges occupy 8…11. Rank those two permutations separately, normalizing slice piece IDs by subtracting eight.

Pack these tables without symmetry reduction:

| Table | Shape | Value type |
|---|---|---|
| twistMove | 2,187 × 18 | UInt16 |
| flipMove | 2,048 × 18 | UInt16 |
| sliceMove | 495 × 18 | UInt16 |
| cornerPermMove | 40,320 × 10 | UInt16 |
| edgePermMove | 40,320 × 10 | UInt16 |
| slicePermMove | 24 × 10 | UInt8 |
| twistSliceDistance | 2,187 × 495 | UInt8 |
| flipSliceDistance | 2,048 × 495 | UInt8 |
| cornerSlicePermDistance | 40,320 × 24 | UInt8 |
| edgeSlicePermDistance | 40,320 × 24 | UInt8 |

Generate exact shortest distances in each abstraction by breadth-first search from its goal with that phase's move set. Initialize unvisited values to 255, fail generation if any required reachable entry remains unresolved, and check integer ranges before serialization. No compressed modulo-distance trick, symmetry mapping or unproven extra pruning in v1.

`h1 = max(twistSliceDistance, flipSliceDistance)`. IDA* searches to the first phase-one goal with iterative limits h1…12. From that subgroup state, `h2 = max(cornerSlicePermDistance, edgeSlicePermDistance)` and IDA* searches h2…18 to solved. Reset previous-move history at the phase boundary. The first subgroup state suffices mathematically because every subgroup state can be solved within the phase-two bound; it need not yield the shortest combined solution. Search omits consecutive turns of the same face within a phase (they combine to one legal move), but adds no opposite-face ordering or cross-phase pruning in v1. The result is at most 30 face turns before optional adjacent-same-face simplification, which must preserve replay outcome.

At each IDA* node, test the phase goal correctly at depth zero, and prune only when the admissible bound exceeds remaining depth. Check timeout/cancellation on entry, at the required node cadence and phase transitions. Fully exhausted valid bounds without a solution are an internal invariant failure, never an “unsolvable cube” result. Runtime replay remains mandatory.

Binary format v1: 8-byte magic `CUBETBL1`, UInt32 little-endian version (=1), UInt32 table identifier, UInt32 rows, UInt32 columns, UInt32 element-byte-width, UInt64 payload-byte-count, then row-major little-endian payload. SHA-256 of each complete file is in a bundled JSON manifest with generator version and source commit. Reject arithmetic overflow, wrong identifiers/dimensions, unexpected trailing bytes, truncated payload, unknown version and hash mismatch. File size is bounded by manifest before allocation. Do not persist native Swift memory layouts.

The generator and independent validator are separate executables/tests; rebuild resources twice in clean directories and compare bytes. A development generator can be slower than the phone runtime. End-user devices load bundled tables and never need a network or first-launch table download.

## 5. Image pipeline decisions

Record pixel-buffer orientation at capture. Normalize to unmirrored upright coordinates, apply the reviewed four-corner homography and retain floating-point samples. Convert explicitly tagged sRGB image values to linear RGB and then CIELAB using a documented D65 transform. Do not compare camera YCbCr bytes directly with RGB swatches. Sampling excludes crop borders and clipped pixels; produce a median color and robust spread estimate per cell.

Reject non-finite, out-of-image, repeated, self-crossing or near-collinear corner coordinates before computing the transform; require a convex quadrilateral with consistently ordered corners. Clamp neither a bad crop nor an empty sample into a plausible color. Downsample capture processing to at most 1,920 pixels on its longest side before rectification, retain at most one frozen frame, and drop queued processing frames when a newer revision arrives. Test singular transforms, zero usable sample pixels, duplicate confirmed center names, lighting change between faces and unsupported color mixtures; show a correction/recapture outcome, not a numeric exception or a guessed legal cube.

Capture all six centers before final classification. Have the user confirm the six center names; assign every non-overridden sticker to the nearest center in CIELAB Euclidean distance. Mark uncertainty using the nearest/second-nearest margin, within-cell dispersion and frame-quality indicators. Treat these scores as heuristics, not calibrated probabilities. Inseparable centers trigger relighting/rescan or manual input; never force a color because a face must contain nine of it.

Calibration is explicit engineering work: train/tune no model; select deterministic thresholds on the 100-session development partition to minimize wrong confident assignments subject to acceptable rejection, record the exact selected parameters in `scan-policy.json`, then freeze them before opening the held-out 200-session test partition. Report a threshold-development failure if the development data cannot meet the goal. Do not invent numeric “accuracy” from an untested threshold. Once held-out data informs a change, move it to development and acquire a new held-out set.

## 6. Implementation tasks and TDD increments

For every numbered increment: write its failing test; run and capture the intended failure; implement; run focused and affected suites; refactor; run the task's exit suite. Commit after a coherent increment or task. Store each task's requirements, test IDs, red/green results and artifact paths in `docs/evidence/task-NN.md`. Behavior may not be waived just because a framework is difficult to automate; combine a deterministic adapter test with a physical check.

### T01 — Repository, package and CI (M0; R14, R20)

Files: existing project, Package.swift, AppDependencies.swift, test plans, Scripts/, docs/.

1. Inspect project/targets/deployment/signing; record name mapping and toolchain. Add the local package and test targets.
2. Demonstrate test discovery by an intentionally failing assertion, then replace it with a meaningful package smoke contract; verify CI reports nonzero on failure and zero after correction.
3. Add scripts that stop on any failure, preserve exit codes through logging, record skipped/discovered tests and upload result bundles even on failure.
4. Add requirement-to-test metadata and an asset-manifest validation entry point before product assets are added.

Exit: clean simulator build and package tests run from documented commands; no credentials in source; CI failure propagation verified. Performance qualification of the finished solver occurs at T04, not prematurely at T01.

### T02 — Mathematics and runtime verifier (M1; R04, R06, R07)

Files: CubeCore sources/tests, Fixtures/Mathematics, test-only geometric oracle.

1. Test bounded parsing and exact face ordering with malformed lengths/labels.
2. For each of the six base quarter-turns, first assert all 54 unique-label destinations against a reviewed golden fixture. Add amounts two/three and inverse tests; do not rely only on monochrome solved faces.
3. Add all 24 orientations, closure/inverse and move-conjugation tests using the basis table.
4. Add corner/edge extraction and each legality failure independently, including valid balanced cases.
5. Add replay verification: solved+empty accepted, scramble+empty rejected, wrong/malformed/overlong sequence rejected, valid sequence accepted; expose no unverified plan constructor.

Representative test contract (implemented with the package's concrete constructors): `verify([], for: solved)` succeeds; `verify([], for: solvedApplyingR)` fails; `verify([R.inverse], for: solvedApplyingR)` succeeds. Expected facelets for R come from the golden fixture, not from `applying` in this test's arrange phase.

Exit: V01–V03 and runtime-postcondition cases pass; seeded move/validation/verifier mutations are detected. Independent oracle counts the shallow-state corpus.

### T03 — Coordinates and reproducible tables (M2; R06, R13, R20)

Files: Cubies.swift, Coordinates.swift, Tables.swift, Tools/TableGenerator, resources and coordinate tests.

1. Test every rank/unrank round trip and boundary, including slice goal 494 and rejected out-of-domain phase-two states.
2. Generate each transition from independently implemented cubie operations; compare with the facelet oracle across all compact domains.
3. Test exact small abstraction distances before running each full BFS; independently recompute all four distance tables and compare every value.
4. Test binary resource round trips, endian/header/count/hash/truncation/overflow failures before adding the loader.
5. Generate and package versioned tables; verify clean regeneration twice and size budgets.

Exit: V04 passes with every table entry checked, no unresolved sentinels, complete manifest and notices. Record generation time/memory separately from runtime memory.

### T04 — Real search and qualification (M2; R06, R13)

Files: Search.swift, SolverService.swift, real solver tests, pinned reference tooling, performance harness.

1. Test phase goals at depth zero, one-move solutions, just-below/at-depth bounds and each pruning comparison boundary.
2. Implement deterministic phase-one IDA*, then phase two; target states already in the subgroup and those requiring phase one.
3. Inject fake monotonic clock/cancellation; test cancellation before load, during both phases and before verification. Distinguish deadline/probe-limit/reference failures from invalidity.
4. Test concurrent job isolation, stale revision rejection and a deliberately wrong solver answer blocked by Replay.
5. Run exhaustive shallow states, known-hard fixtures, the PR corpus and reference differential checks. Execute 1,000-state physical device benchmarks before proceeding with a performance claim; if hardware is absent continue independent UI work with that gate explicitly open.

Exit: V05–V06 pass, correct finite-corpus solutions and measured resource budget. Any missed timing target is a named gate failure, not a claim that the design is impossible or complete.

### T05 — Session, storage and recovery (M3/M4; R05, R09–R11, R18)

Files: CubeSession, GuidePlanner.swift, SessionStore.swift, reducer/storage tests.

1. Table-test every state/event pair with explicit accepted/ignored/rejected result; solve only after consent and confirmed validity.
2. Test regrip planning for 24×18 combinations and physical-state invariance; every emitted move reconstructs the original canonical solver move.
3. Test two-phase acknowledgement: event starts save; only matching save success advances; duplicate/stale event ignored. Inject crash at each boundary and write failure after physical turn.
4. Test persisted session decode, replay, checksum, size/index/pose limits, schema handling and data deletion.
5. Test resume-before, resume-after, uncertain state, partial regrip and recovery-rescan invalidation.

Exit: V09/V11 pass with fake persistence and real filesystem fault tests; no silent repeated physical turn or false durable save.

### T06 — Complete manual-entry product flow (M3; R01, R03–R06, R15)

Files: Home/Editor/Settings screens, application composition, ManualFlowTests.

1. UI-test empty state, explicit centers, all 54 editable cells, invalid input and correction.
2. Test solved/manual wording, Solve/Not now, cancellation, timeout and verified plan display through real package components.
3. Test replace/keep existing work, practice isolation, Help navigation and persisted settings.

Exit: manual offline flow works in the actual app, not just SwiftUI previews; permission denial does not block it. S01/S05/S06/S07/S11 states covered.

### T07 — Production graphics and animation (M4; R07, R08, R12, R16)

Files: CubeScene.swift, MoveAnimator.swift, Assets.xcassets, vector/generator sources, SceneTests.

1. Assert geometry/sticker membership and exact transforms before drawing the 3D cube; use uniquely labeled fixtures.
2. Test regrip versus layer-turn endpoints, pause/replay/reset and long-run snapping with all move/pose combinations.
3. Produce A01–A07 and record provenance. Verify missing asset causes manifest failure; test light/dark and labels before accepting final art.
4. Add original icon to actual app/archives; test readable installed icon and launch-screen continuity.
5. Implement Reduce Motion before/after alternative; test maximum text size and narrow/landscape screens.

Exit: V10 and visual QA pass; every required asset exists, no placeholder art, no animation drift. QA is both geometric assertions and human inspection.

### T08 — Guidance, audio and haptics (M4; R08–R12, R17)

Files: Guide screens, AudioCoordinator.swift, HapticFeedback.swift, phrases.json, Audio/, AudioTests, GuideFlowTests.

1. Test action identity/caption/audio mapping using fake player/clock; wrong narration direction and doubled acknowledgement must fail tests.
2. Obtain/record N01–N30 and E01–E03, editable masters and usage rights. Validate codecs, duration, peaks, filenames and exact caption coverage; listen to every phrase.
3. Implement playback-to-animation sequencing, interruption, replay, pause and route loss; confirm physical Silent switch, Bluetooth disconnect and VoiceOver behavior on a phone.
4. Test resume/mismatch and completion types; N28 can never play for manual/user-confirmed-only completion.

Exit: V09/V13 pass; all narration/effects are bundled and rights recorded. Missing recordings remain a blocking media task, not a caption-only “complete” feature.

### T09 — Guided camera and correction (M5; R02, R03, R10, R13)

Files: CameraCapture.swift, CubeScan, Scan screens, scan-policy.json, labeled Scans fixtures, ScanFlowTests.

1. Test pixel/crop/homography transforms on calibration grids before sampling real sticker images.
2. Test six-center calibration lifecycle, uncertain and manually overridden readings, rotated face correction and dependent reclassification.
3. Implement real capture/permission/interruption lifecycle; test stale frames and orientation at capture time.
4. Collect development data; freeze thresholds; process held-out whole sessions and report exact ground-truth states. Correct and verify all 200 through the real editor.
5. Run camera→review→real solver→guide→verification-camera integration; label fixture injection and live capture separately.

Exit: V07–V08 pass with accuracy metrics and live camera trials. No recognition claim based only on synthetic colored squares.

### T10 — Accessibility and full physical workflow (M6; R08, R10, R12, R15–R17)

Files: all screens, help illustrations/text, accessibility tests and physical QA reports.

1. Test VoiceOver order/labels/actions, Dynamic Type, Differentiate Without Color, Reduce Motion, mute and large touch targets across every S screen.
2. Run 20 novice sessions including ten supervised children; include actual turns, regrips, mistakes and resume. Record adult assistance separately from engineer intervention.
3. Verify all face-motion/audio combinations physically; confirm a new user distinguishes regripping the cube from turning a layer.
4. Fix observed usability defects with regression cases before rerunning affected checks; update changed guidance artwork/audio together.

Exit: accessibility evidence and ≥18/20 correctly completed novice trials; any inaccessible essential control or misleading move blocks release.

### T11 — Harden and qualify release build (M6; R01, R13, R14, R18)

Files: performance tests, Release test plan, resource/privacy manifests, Scripts/test-release, evidence manifest.

1. Run million-state, exhaustive, mutation, real-image and lifecycle gates on the exact candidate commit; preserve reproducible failures.
2. Test signed/packaged assets with networking disabled from first launch, after reboot and during recovery. Check app-created network connections, not unrelated OS traffic.
3. Measure cold/warm latency, peak memory, frame responsiveness and resource sizes on all physical targets. Sustain 30 fps or better during guide animation on baseline devices; allow Reduce Motion to render static frames without a continuous loop.
4. Test 100 consecutive scan/manual/solve/recover cycles for bounded resource retention, low storage, corrupted saves, foreground interruptions and upgrade from a saved prior test build.

Exit: all required automated/media/device checks pass on the candidate; collect `.xcresult` and package reports. No hardware access or missing voice asset means “blocked qualification”, not “tests passed”.

### T12 — Package, hand off and submit when authorized (M7; R19, R20)

Files: release-runbook, distribution archive, store copy/screenshots/privacy/support drafts, notices, release evidence.

1. Obtain owner inputs from specification section 15; create real final identifiers/signing only from those inputs.
2. Validate Release archive and symbols, production entitlements, camera usage text, privacy declarations/API reasons and all shipped assets/notices; ensure no fixture injection/debug bypass is reachable in Release.
3. Produce actual A08 screenshots, store description, support/privacy URLs and review notes describing physical cube use plus the labeled practice/manual path. Complete actual age-rating, country, price and export fields with the account owner.
4. After authorization, upload to TestFlight, test that distributed build with offline core scenarios, then submit the same qualified build for review. Record review responses and fixes; changed code/assets require affected regression and release checks.
5. Release only under owner authorization. Report build number, submission/approval/release status and link; if rejected, report the reason instead of claiming shipped.
6. Deliver repository, architecture/runbook, asset masters, table generators, notices, reproduction commands, test evidence and known limitations. Define owner support intake and patch process: reproduce issue → failing regression → fix → requalification → owner-authorized update.

Exit: separately report archive ready, TestFlight-qualified, submitted, approved and released. Until actual external events occur, those statuses remain pending.

## 7. Evidence commands and completion rules

At T01, make the following repository commands executable and document their exact toolchain/simulator destination resolution. Scripts must fail clearly when a required runtime/device is unavailable; they cannot silently skip it.

```sh
swift test --package-path Packages/CubeKit
./Scripts/test-pr.sh
./Scripts/test-nightly.sh
./Scripts/validate-assets.sh
./Scripts/test-release.sh
./Scripts/build-release.sh
```

PR/nightly scripts invoke the mapped app scheme/test plan through `xcodebuild test`, select an installed simulator by recorded UDID and preserve `.xcresult`. Release script accepts an explicit qualification-device inventory and aggregates desktop/simulator/device/manual evidence; it fails if any mandatory evidence entry is absent. Archive script uses actual signing configuration and never fabricates a team ID.

No task is done merely because unit tests pass: its specified integration, media or physical deliverable is also required. External-input gaps should block only dependent work; continue independent tasks and keep a single visible blocker ledger. Finish only when all R01–R20 requirements have the required evidence, or report precisely which product/release gates remain open.
