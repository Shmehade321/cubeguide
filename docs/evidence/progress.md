# Execution ledger — Documentation/cube-app-implementation-plan.md

Baseline: 78f7fbc. User authorized full implementation with TDD, quality checks and commits per coherent task/increment. No product delivery or publication is claimed.

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
| T05 Session/storage | running: guide/manual/scan storage and durable discard implemented; full lifecycle pending | task-05.md |
| T06 Manual flow | running: Home/editor, validation/solver result UI, offline Help, persisted Settings, isolated practice and calculation-state UI coverage | task-06.md |
| T07 Graphics | running: static preview plus animation and initial guide/comparison/recovery/completion increment qualified locally; live label propagation qualified; overlays, Reduce Motion, broader accessibility, artwork and media qualification pending | task-07.md |
| T08 Guidance/audio | notRun | — |
| T09 Camera | notRun | — |
| T10 Accessibility/physical | notRun | — |
| T11 Qualification | notRun | — |
| T12 Distribution | notRun | — |

## External gates

Physical phones/cubes, supervised participants, owned human narration, final store identity/audience/price/countries, support/privacy URLs, signing account and submission/release authorization are not evidenced. Independent implementation continues. Existing bundle identifier is preserved, not certified as final store identity.

## Shipping status

Code: foundation, cube mathematics, independently validated tables and real verified search implemented; session workflow, guide planning, durable-save protocol and recovery decisions implemented; guide archive/restore and filesystem store implemented; scan command coordination, durable draft discard and scan-to-manual fallback implemented; Home, durable manual editor, validation review markers/consent, real solver result, entered-color completion, offline Help, persisted Settings/reset UI and isolated practice implemented; calculation cancellation/error UI and static manual/practice 3D preview qualified locally; full lifecycle and remaining manual product flow integration in progress. Automated qualification: not complete. Media/device qualification: not run. Archive: not ready. TestFlight/submitted/approved/released: not performed.
