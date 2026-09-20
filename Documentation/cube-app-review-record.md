# CubeGuide — Four-Round Specification Review

20 September 2026 · Review scope: specification, verification plan and implementation/delivery contract. This was a sequential self-review by the same agent, not an independent multi-agent audit.

## Verdict

The initial documents were a useful architecture and testing outline, but were not sufficient to promise a finished, shippable product from an agent following them. Revision 2 closes the concrete gaps identified below and adds implementation ownership and distribution requirements.

It would still be false to call this “100% accurate”, “every possible edge case covered” or “guaranteed to ship”. No app implementation, media production, physical testing or App Review has occurred during this review. The pack now states those obligations and prevents them from being silently skipped; it cannot substitute for their execution.

## Round 1 — Scope and technical correctness

| Finding | Change |
|---|---|
| Solver was not selected and theoretical 12/18 phase bounds were not reconciled with the suggested library | Inspected the reference source; pinned test-only revision; specified an original conventional Swift solver with exact coordinates, move sets, search bounds and table layouts. |
| Reference defaults could be mistaken for completeness | Confirmed `Search.java` has `MAX_DEPTH2 = 12` and probe limits. These are no longer presented as proof of our 18-depth phase-two contract. |
| First-face classification implicitly depended on centers not yet scanned | Defined provisional per-face readings, six-center final calibration and re-review after dependent center changes. |
| “Top edge” and hidden-face turns were underspecified | Added signed coordinate bases, exact canonical face tops, deterministic acknowledged regrips and front-only instructional turns. |
| Runtime verifier could be overstated as recognition verification | Explicitly separated exact scanned state from mathematically legal state and required ground-truth camera evaluation/user review. |
| Asset/table correctness could be reduced to hashes | Required independent transitions and distance validation; hashes remain an integrity check. |

Source inspection: [min2phase pinned revision](https://github.com/cs0x7f/min2phase/tree/4d183b9eff8119cac72bc50ef35a7d8990740e06). This review did not run that reference solver or certify its licensing for a production port; no port is prescribed.

## Round 2 — Complete user experience and product assets

| Finding | Change |
|---|---|
| Screen set and error/empty/loading navigation were missing | Specified S01–S11, manual fallback, consent, practice isolation, completion origins and saved-work replacement. |
| Graphics/icons were described only as “realistic 3D” | Added A01–A08, geometry, palette/labels, icon source/provenance, help/capture diagrams, installed-build and store screenshot QA. |
| Audio was a wish rather than a production deliverable | Added N01–N30 exact scripts, E01–E03 effects, rights/master/bundle requirements, mute/route/interruption/VoiceOver rules and physical listening checks. |
| Haptics, animation pacing and reduced motion lacked rules | Defined defaults, timing, feedback events and static before/after alternatives. |
| Physical undo/resume could repeat a move already made | Added pending-action identity, save-before-display/save-before-advance, before/after comparison and uncertain-state rescan. |
| Local deletion/privacy/storage details were incomplete | Defined retention, file limits, no raw-frame persistence, late-write deletion protection, local help/privacy and release archive audit. |

## Round 3 — TDD, integration and shipping

| Finding | Change |
|---|---|
| Test coverage ended at R14 and omitted production media/store requirements | Expanded to R01–R20, V01–V17, explicit task ownership and required physical/external evidence. |
| Milestones were not a concrete implementation handoff | Added T01–T12 with files, shared contracts, red/green increments and exit gates. |
| Solver benchmarks appeared in foundation before solver implementation | Moved qualification to T04/M2 and retained explicit unavailable-hardware status. |
| Randomized counts could mask duplicates or impossible quotas of short states | Specified direct-state and four long-scramble strata, cross-corpus deduplication and a separate exhaustive shallow set. |
| CI could silently skip, retry away failures or accept updated snapshots | Added discovery/skip/failure propagation, mutation catalog, manual baseline review and evidence invalidation rules. |
| Roadmap stopped before packaging and store delivery | Added M7/T12, signed archive, distributed TestFlight checks, real store assets, owner inputs, submission/release status and maintenance handoff. |
| “Child friendly” could be mistaken for a chosen store category/rating | Made audience/Kids category and age-rating answers owner inputs, with conditional required work rather than fabricated approval. |

Current primary distribution references were checked: [submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [privacy declarations](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [age ratings](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating) and [review guidelines](https://developer.apple.com/app-store/review/guidelines/). These references inform release tasks, not a guarantee of approval.

## Round 4 — Cross-document and adversarial walkthrough

Re-read the revised contracts as an implementer following them: ordinary scan/solve; wrong but legal recognition; mid-turn interruption; physical acknowledgement with failed save; cancellation followed by stale callback; delete with a pending write; camera-denied use; missing narration; fresh-install offline; owner inputs absent at submission.

Corrections made during this pass:

- Replaced old “independently sourced production solver” language with the actual original implementation decision.
- Reconciled confirmed cube state with the explicitly labeled expected-after preview.
- Removed a diagnostic policy contradiction that would have stored sticker input despite the privacy contract.
- Reconciled the first phase-one endpoint approach with full phase-two bounds, rather than requiring unnecessary endpoint enumeration.
- Defined interruption destinations by workflow state so cancelling search cannot create a resume screen without a solution plan.
- Separated onboarding demonstration speed from the persisted guide preference.
- Updated device coverage, all requirement IDs, asset suites, distribution milestones and table validation throughout the pack.
- Deleted the obsolete Xcode/Codex setup guide as requested.

### Executed design checks

A throwaway integer-geometry checker, separate from any future product code, evaluated the written face bases and rotation signs. It produced:

| Check | Result |
|---|---|
| Face coordinates | 54 unique sticker positions/normals; six right-handed face bases |
| Moves | 18 bijective face permutations; fixed centers; inverse/four-quarter/half-turn identities |
| Proper orientations | 24 orientations, determinant +1 |
| Regrip targets | All 144 pose/target-face combinations reachable, at most two whole-cube quarter regrips to bring a face front |
| Shallow unique states | Exact depths 0–4: 1, 18, 243, 3,240, 43,239; cumulative 46,741 |
| Table payload arithmetic | 5,815,005 bytes for the declared ten tables, excluding headers/manifest/temporary generation memory |

These results check finite written conventions and arithmetic only. They do not execute the production solver, prove its implementation, measure iPhone performance, validate image recognition, or review final artwork/audio. The temporary checker stays in working files; future product tests must independently reconstruct and verify the conventions.

Document checks verify local links, contiguous requirement/test/task/milestone identifiers, requirement ownership coverage, removal of the setup file, balanced code fences and absence of unfinished placeholder markers. They are documentation checks, not app tests.

## Remaining obligations — explicitly not fulfilled by document review

| Obligation | Current status | Why a document cannot close it |
|---|---|---|
| Implement product and observe real red/green cycles | Not started | No actual app repository was supplied in this task. |
| Benchmark original solver and table generator | Not run | Search/data structures need implementation and device measurements. Performance targets are gates, not predictions. |
| Calibrate deterministic recognition thresholds | Not run | Requires labeled development captures; parameters are frozen before held-out evaluation. |
| Produce graphics/icon/narration/effects and record rights | Not produced | Inventories/scripts are specified; source assets and human recordings still need creation. |
| Physical minimum-OS/current-OS and novice validation | Not run | Requires actual phones, cubes and supervised participants. |
| Final store identity/category/price/countries and support/privacy URLs | Owner input required | These are product/account facts the agent cannot invent. |
| Signing, TestFlight, review and public release | Not performed | Requires the real project/account, passing evidence, authorization and external outcomes. |

The pack is substantially more complete and provides a defined route to a full product. An agent must still exercise engineering judgment inside the stated contracts, collect real evidence and escalate unavailable external inputs. Claiming that following documents alone guarantees delivery would be misleading.
