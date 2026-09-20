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

## Tasks

| Task | Status | Evidence |
|---|---|---|
| T01 Foundation | running | task-01.md |
| T02 Mathematics | notRun | — |
| T03 Tables | notRun | — |
| T04 Search | notRun | — |
| T05 Session/storage | notRun | — |
| T06 Manual flow | notRun | — |
| T07 Graphics | notRun | — |
| T08 Guidance/audio | notRun | — |
| T09 Camera | notRun | — |
| T10 Accessibility/physical | notRun | — |
| T11 Qualification | notRun | — |
| T12 Distribution | notRun | — |

## External gates

Physical phones/cubes, supervised participants, owned human narration, final store identity/audience/price/countries, support/privacy URLs, signing account and submission/release authorization are not evidenced. Independent implementation continues. Existing bundle identifier is preserved, not certified as final store identity.

## Shipping status

Code: foundation in progress. Automated qualification: not complete. Media/device qualification: not run. Archive: not ready. TestFlight/submitted/approved/released: not performed.
