# Execution ledger — Documentation/cube-app-implementation-plan.md

Baseline: 78f7fbc. User authorized full implementation with TDD, quality checks and commits per coherent task/increment. No product delivery or publication is claimed.

## Current continuation — 21 September 2026

The final local source adds the complete A04 Help illustration set, reproducible E01–E03 effect assets with editable PCM masters, and an editable A01 SVG master. The final clean PR Xcode plan passed 66 tests with zero failures/skips, including 20 UI tests, and the generic unsigned Release device build succeeded. The asset gate is now missing only A08 and N01–N30. These results do not satisfy the physical, human-media, corpus-calibration, minimum-OS, signing or distribution gates described below.

Resumed T07 from committed checkpoint `cdc58ee`. The iOS 18.5 preview crash has an independent bare-ARView reproducer and remains an open minimum-OS qualification issue. On explicitly selected iOS 26.5, the real product passed 100 preview/Home/Resume cycles across three diagnostic repetitions and two full suites. Test-only fixes disambiguate nested dialog actions and scroll guide controls into view. After retaining the first full run's three failed guide tests and validating their correction, the fresh full PR completed with all 56 simulator tests passing, zero failures/skips, and all package/storage/solver/reference stages passing. All 211 non-document inputs match the run snapshot. See the [concise investigation and evidence links](t07/runtime-investigation.md).

The affected iOS 18 runtime now uses the labeled static renderer rather than constructing ARView; iOS 26 and later retain the animated renderer. On iOS 18.5, focused product tests passed a full practice-guide recovery path and 20 preview/teardown/Home/Resume cycles. This mitigates the known simulator failure but does not replace physical minimum-OS qualification. A07 completion artwork is implemented with retained final state/palette/pose, static Reduce Motion rendering, scrolling and separate physical confirmation. The repository remote is configured for the supplied GitHub repository.

Current hardening adds queued AVFoundation lifecycle ownership, stale/duplicate capture rejection, crop reprocessing with cancellation, central-40-percent sampling, fail-closed installed scan policy, advisory capture-quality hints, full scan review controls, audio route/interruption synchronization, pose narration composition, lifecycle/idle-timer handling, replacement consent, a privacy manifest and a typed exact-commit qualification gate. Local table reproduction and all core/solver/session mutation catalogs pass. Ordered isolated corpus shards make the million-state and pinned-reference gates practical without weakening case counts or failure propagation. The final clean full-plan run and release corpus are recorded only after the source is committed; physical camera/media/accessibility/performance evidence remains open.

## Rulings and pre-flight

- Ruling: work in the supplied checkout on `codex/cubeguide-implementation`, preserving the user's uncommitted documentation/project references. The current-worktree instruction and continuous execution take precedence over an optional isolated checkout workflow. No main-branch implementation.
- Map planned CubeGuide paths to existing `cubeguide`, `cubeguide.xcodeproj`, `cubeguideTests`, `cubeguideUITests`; canonical supplied contracts remain under Documentation. Execution/evidence/runbooks live under docs.
- T02 → T03/T04: facelet engine and cubie solver must implement moves independently; only the test geometry oracle cross-checks both. No shared move generator.
- T02/T04 → T05/T06: only Replay can construct VerifiedPlan; no unverified instructions or solver mocks in integration.
- T05 → T07/T08: one immutable GuideAction identity drives pose, scene, captions and audio. Durable pending action before preview; durable acknowledgement before next action.
- T09 → T05/T06: six-center classification is provisional until all centers exist; manual overrides survive reclassification; accepted input increments revision.
- T07/T08/T09 → T10/T11/T12: automated results cannot replace physical, listening, image-corpus or distribution evidence.
- Task code will use the supplied task headings directly as briefs; their T01–T12 identifiers and committed evidence files are the durable tracking system.

- Execution-order refinement at T06: T05's implemented manual/session/storage contracts and 17-mutation catalog are qualified locally. Final camera-classified input acceptance depends on T09 classification/capture work; physical lifecycle gates also remain open. Start independent T06 manual UI integration against those real contracts while keeping T05 explicitly running. This does not waive any T05 or release gate or substitute the manual flow for the full product.

## Tasks

| Task | Status | Evidence |
|---|---|---|
| T01 Foundation | local exit passed; remote CI not run | task-01.md |
| T02 Mathematics | automated exit passed; physical golden check open | task-02.md |
| T03 Tables | local exit passed; remote CI not run | task-03.md |
| T04 Search | automated exit passed; physical qualification open | task-04.md |
| T05 Session/storage | running: guide/manual/scan storage, durable discard and reviewed-scan acceptance implemented; remaining physical storage/lifecycle qualification pending | task-05.md |
| T06 Manual flow | running: Home/editor, validation/solver result UI, offline Help, persisted Settings, isolated practice and calculation-state UI coverage | task-06.md |
| T07 Graphics | running: static iOS 18 safe renderer and animated iOS 26 renderer pass focused simulator product paths; A01/A04/A07 implemented; physical minimum-OS, broader accessibility and visual qualification open | task-07.md |
| T08 Guidance/audio | running: exact phrase/pose composition, caption fallback, ambient sequencing, reducer-synchronized interruption handling, E01–E03 and preference-gated haptics implemented; owned human recordings and physical listening/routes open | task-08.md |
| T09 Camera | running: deterministic central sampling/classification, queued AVFoundation lifecycle, frozen/crop review, quality hints, correction/manual fallback and fail-closed 48-sticker review implemented; calibrated policy, real corpus and live-device trials open | task-09.md |
| T10 Accessibility/physical | running: simulator Reduce Motion, large-text, orientation, non-color labels and accessible Help coverage pass; VoiceOver/device and 20 novice sessions remain open | task-10.md |
| T11 Qualification | running: infrastructure, table reproduction, mutation catalogs and generic unsigned Release analysis pass on working source; final clean full plan, release corpus and device/media/lifecycle evidence open | task-11.md |
| T12 Distribution | notRun; phone validation runbook prepared, configuration/deployment intentionally deferred | phone-validation-runbook.md |

## External gates

Physical phones/cubes, supervised participants, owned human narration, final store identity/audience/price/countries, support/privacy URLs, signing account and submission/release authorization are not evidenced. Independent implementation continues. Existing bundle identifier is preserved, not certified as final store identity.

## Shipping status

Code: all planned offline app flows are implemented, including durable manual and camera input, conservative review/correction, real verified solving, recoverable guidance, completion, Help, Settings and practice. Phone-validation safeguards and a physical test runbook are present. Automated release qualification is not complete until the final clean full plan and million-state corpus pass on the candidate commit. Human narration, real camera corpus, physical device/accessibility/performance/lifecycle trials and novice studies are not run. Archive: not ready. TestFlight/submitted/approved/released: not performed.
