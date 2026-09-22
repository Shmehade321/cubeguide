# Phase 4 ceiling audit — R01–R20 vs implementation (22 September 2026)

Worktree: `development`, HEAD `989044f` + uncommitted app-UI/test/docs changes
(`Packages/` and `Tools/` identical to HEAD). Statuses: **met**
(machine-verified this session), **partial** (app work verified, external
evidence missing), **blocked** (needs humans, devices, or owner inputs).

## Automated requirements

| Req | Status | Evidence |
|---|---|---|
| R01 Offline operation | partial | Fresh-install offline UI paths pass on iOS 18 + 26.5 simulators (`testOfflineHelpFromHome`, manual/camera fallbacks). Distributed-candidate disconnected install needs TestFlight build: blocked. |
| R02 Complete scan | partial | Six-slot capture, progress, duplicate protection covered by unit + UI tests. Physical six-face capture in pose order: blocked (devices). |
| R03 Correctable recognition | partial | Face review, editable labels, rotation, rescan, manual fallback tested. Held-out 200-session corpus + frozen thresholds: blocked (camera corpus). |
| R04 Legal-state validation | partial | V01–V03 package suites pass (incl. parity/orientation mutations killed). Physical golden-fixture check: blocked. |
| R05 Consent/classification | met (sim) | Solved/offer/invalid branches UI-tested incl. consent/decline and saved Home. |
| R06 Verified solution | partial | 1M/1M + 100k/100k + 10k/10k verified, zero timeouts; Java differential green; replay-before-display enforced. Device cold/warm p95/p99: blocked. |
| R07 Matching 3D cube | partial | Geometric scene tests + static (iOS 18) / animated (26.5) renderer paths green. On-device visual match: blocked. |
| R08 Understandable moves | partial | Action identity across pose/scene/caption/audio tested; regrip/turn separation tested. Listening + comprehension trials: blocked. |
| R09 Explicit progress | met (sim) | Exactly-once acknowledgement, duplicate-tap, replay-no-advance covered incl. 17 session mutations killed. |
| R10 Recovery/completion | partial | Recovery/resume/expectedSolved/completed flows UI-tested with distinct user-vs-scan confirmation. Physical wrong-turn recovery: blocked. |
| R11 Safe resume | partial | Atomic save, crash injection at acknowledgement boundaries, 33 process-kill storage cases green. Locked-device/disk-full on hardware: blocked. |
| R12 Accessibility | partial | Reduce Motion static path, large text, orientations, non-color labels pass on simulators; computed sRGB contrast ≥4.5:1 on all 6 label pairs (red/green thin). VoiceOver on device, silence switch, rendered contrast measurement: blocked. |
| R13 Responsive execution | partial | Cancellation/timeout/stale-result/resource-failure UI outcomes tested. Device latency/memory/thermal/frame gates: blocked. |
| R14 TDD/evidence | partial | Red/green records in `t04/`; candidate-commit (`284effd`) full PR plan green (exit 0, 81/0/0); unrun gates recorded here + task-11. |
| R15 Screens S01–S11 | met (sim) | All screens/states implemented and UI-tested; rebuilt UI reviewed via `ReviewShotsUITests` attachments. |
| R16 Visual assets | partial | A01–A08 implemented + provenance recorded + registered (18 Release PNGs, dimensions verified, content inspected). Human visual QA on device + owner store-listing review: blocked. |
| R17 Sound/haptics | blocked | E01–E03 + sequencing/interruption/haptics implemented and tested; N01–N30 human recordings + rights + listening sign-off missing. Caption fallback verified. |
| R18 Data lifecycle | partial | Bounded/versioned storage, deletion generation, backup exclusion, privacy manifest tested. Installed-build storage audit: blocked. |
| R19 Distribution | blocked | No owner identity/URLs/signing; no archive, TestFlight, submission, or release. Runbook prepared (`phone-validation-runbook.md`). |
| R20 Handoff | partial | Architecture/runbook/generators/licenses present; typed `release.json`/`nightly.json` honestly absent (require device/media/archive evidence). |

## Blocker ledger (all external; no independent work remains blocked behind them)

1. Physical iPhones (min-iOS 18.x + current) + cubes → R01/R02/R06/R07/R10/R11/R12/R13 device gates.
2. 300-session labeled camera corpus + calibration time → R03 (+R02 accuracy).
3. Licensed human N01–N30 recordings + listening panel + audio routes → R17 (+R08/R12).
4. 20 supervised novice trials (10 children) → R10/R12/R15 usability gates.
5. Owner: bundle ID/signing, store metadata/URLs/price/countries, submission authorization → R19, A08 final sign-off.
6. Final candidate commit + clean full-plan rerun + archive (follows 1–5 and this worktree's commit).

## Deliberately not done

- No synthesized narration passed off as N01–N30; no fabricated device identities, URLs, or approvals.
- No test timeouts weakened for the 26.5 simulator flake (diagnosed, recorded in task-11.md).
- No `release.json`/`nightly.json` with unearned `passed` rows (checker correctly reports Blocked).
