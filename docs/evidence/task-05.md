# T05 — Session, storage and recovery

Status: running. Base: 436cd84. R05/R09–R11/R18; V09/V11. T04 automated work is committed; physical solver qualification remains open under the plan's independent-work allowance.

## Increment 1 — consent, revisions and action planning

The new CubeSession module implements the initial workflow through action preparation and comparison: explicit manual start/replacement, real legality classification, consent/decline, retained confirmed input, cancellation, stale-result rejection, wrong-original rejection, typed solve failures and one extended timeout retry. Revision overflow is bounded; cancellation remains possible at the last revision without allowing a later stale result. A real service integration test consumes an emitted solve command and returns a verified plan.

The transition table currently covers all nine implemented phases against ten event forms (90 combinations). Later guide, saving, completion, scan and recovery events/phases must expand that table; this is not a claim that the full specification's state machine is finished. Action preparation computes an immutable pending action, and interruption retains its identity for comparison. No event yet enables preview or physical advancement: durable preparation/acknowledgement are the next increment.

GuidePlanner uses the 24-pose graph in the specified neighbor order, emits minimal acknowledged regrips followed by a front-face demonstration, and preserves canonical puzzle state during regrips. All 24×18 combinations reconstruct the original move; literal identity-pose paths check stable tie-breaking. Action IDs bound the solver index to 0…29 and action index to 0…2, including decoding. The initial identity pose is a display reference; the guide must still require explicit physical alignment before preview in the guidance increment.

Behavioral RED/GREEN observed for starting/replacing work, revision limits, classification/consent, stale/results/retry transitions, planner paths/identity bounds, front demonstrations and preparation interruptions. A first transition-table literal accidentally rejected offer→consent; corrected against the written contract, not counted as a product regression. While wiring interruption, a guard was initially changed on edit instead of cancel; the matrix and interruption tests caught it and the implementation was corrected. The front-demonstration property was initially drafted with the type scaffold; that draft was removed, a nil callable boundary produced behavioral RED, then the derivation was rewritten. No such draft was committed.

Full PR regression passed for this increment. This increment is not the T05 exit: durable preparation and acknowledgements, persistent snapshots, atomic storage/fault injection, before/after/uncertain recovery, deletion and complete lifecycle/state-event coverage remain required. The application has no session UI integration yet. No public shipment is claimed.

## Next implementation constraints

- Extend the shared Session reducer; do not create a second independent UI workflow model. Replace the preparation command with a concrete durable-save payload before exposing any preview/acknowledgement event.
- Reconstruct guidance deterministically from the original verified plan and initial reference pose. After a regrip, preserve the original per-move action numbering; recomputing only from the updated pose must not silently renumber the pending action. A bounded full action sequence (at most 90 entries for 30 moves) is one straightforward representation to verify.
- Physical alignment is explicit. The initial identity pose is a required holding reference, not evidence of the user's actual pose. Persist/validate alignment and guard preview accordingly.
- Store before enabling preview, then store acknowledged pose/index before the following action. Duplicate/stale callbacks must preserve the last durable state; save failures enter physical comparison before retry.
- Persist and bound semantic center/display mapping outside mathematical identity. Manual input must supply explicit centers; never infer a manufacturer palette when adding the editor.
- The final T05 exit still requires all specified workflow pairs, real filesystem crash/write/locked/corrupt-schema tests, restore/replay, before/after/uncertain decisions, cancellation/deletion generations and late-write protection.

Ruling: expand the state/event matrix as each planner/persistence-dependent state becomes implementable, rather than claiming all future states pass from placeholder transitions. The complete specification matrix is still mandatory at T05 exit. Cost if wrong: missed interactions until the final matrix expansion; explicit enum coverage currently forces each added phase into the table.

Interface mapping for this module: `SessionReducer.reduce(_:event:)` implements the planned pure reducer; `GuidePlanner.actions(for:at:state:sessionRevision:moveIndex:)` creates bounded ActionIDs internally. All consumers must use these shared types. Initial action preparation remains a command boundary until the storage increment supplies its durable payload and acknowledgement events.


## Increment 1 regression

`SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t05-workflow-pr Scripts/test-pr.sh` exited 0: 81 Swift package tests (17 new session/planner tests), 34 Python tests and three simulator app/UI tests, with no skipped or failed tests. The unchanged solver also passed the complete 10,000-state PR corpus, 46,741 shallow states, eight named cases and pinned reference comparisons. All non-document source hashes match the pre-test snapshot. Reports/red transcripts and package output are under `t05/`; full local artifacts are under `Artifacts/t05-workflow-pr/`.

This is a committed coherent T05 increment, not T05 completion or an implemented guide UI. Next: durable action preparation, explicit alignment, exactly-once acknowledgements and bounded storage/recovery.

## Increment 2 — durable-save protocol and physical comparison

The reducer now emits concrete GuideSaveRequest candidates. Preparation must succeed before alignment/play; acknowledgement retains the previous progress until its matching save succeeds. The next action requires a separate preparation save. Immutable GuideProgress reconstructs the full timeline from the verified original plan, preserving action IDs across regrips and restored offsets. Playback IDs reject late completion callbacks; preview completion never acknowledges a physical action.

Before/after/uncertain comparison handles interrupted preparation, interrupted acknowledgement and failed writes. Comparison retries use a new save ID. Backgrounding stops preview and removes alignment permission; a pending write settles before a next action can be prepared. A failed save retains the prior reducer progress. This is a callback protocol, not yet proof of filesystem durability: the real atomic store, crash injection and restore validation remain outstanding.

Explicit CenterPalette preserves six user-supplied semantic center names in URFDLB order, separately from mathematical face identity. Construction and decoding reject missing/duplicate/unknown colors; decoding reads at most six entries. No manufacturer arrangement is assumed. Captured display swatches and editor integration remain outstanding.

Behavioral RED/GREEN transcripts: `Artifacts/t05-progress-*.log`, `Artifacts/t05-save-*.log`, `Artifacts/t05-state-protocol-*.log`, and `Artifacts/t05-palette-{red,green}.log`. Focused session protocol run passed 28 tests; palette run passed two more. The expanded workflow matrix covers 14 phases × ten original events; the persistence/playback matrix covers 19 phase/substate fixtures × eleven events. These cover implemented states, not the final camera/completion/deletion matrix.

Ruling refining the prior alignment note: durable pose describes the acknowledged physical reference; alignment permission is ephemeral and must be renewed after interruption/relaunch. Persisting a permission flag cannot establish the actual physical pose after the app closes. Restore must always open comparison, never trust a saved aligned flag. Alignment remains guarded before initial preview.

T05 remains running. Required next work: bounded versioned checksummed storage with replay and pose/index checks, actual atomic filesystem failure tests, restore, deletion generations, remaining completion/recovery states and app integration. No user-facing guide or physical qualification is claimed by this increment.

Increment 2 full regression: `SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t05-protocol-pr Scripts/test-pr.sh` exited 0. All 94 Swift package tests (30 session tests), 34 Python tests and three simulator app/UI tests passed, with zero skipped/failed. The unchanged solver passed the 10,000 unique-state corpus, 46,741 shallow states, named fixtures and pinned-reference comparisons. Non-document source hashes matched the captured test inputs after execution. Portable red/green logs, package output, source identity and simulator summary are under `t05/protocol/`; full local artifacts and `.xcresult` remain under `Artifacts/t05-protocol-pr/`.
