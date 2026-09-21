# T07 preview runtime investigation

This is a navigation aid to preserved evidence, not a release approval. The iOS 18.5 preview failure remains open. No renderer workaround, deployment-target change or simulator-only product fallback has been applied.

## Environment

- App deployment target: iOS 18.0.
- Observed toolchain: Xcode 27.0 (27A266a), Swift 6.4, arm64 macOS 27 host.
- Original failing simulator: iPhone 16 Pro, iOS 18.5, `67DB7428-A25B-4167-8FC2-24F47A392E81`.
- Explicit comparison simulator: iPhone 16 Pro, iOS 26.5, `610EA507-710F-4AA6-943C-AF57C0035F07`.

## What the evidence establishes

| Check | Result | Evidence |
|---|---|---|
| CubeGuide manual preview/Home/Resume on iOS 18.5, ordinary allocator | Multiple crashes; one passing repetition did not clear them | [Chronological record](../task-07.md) |
| Standalone, empty non-AR ARView on iOS 18.5 with Guard Malloc | Invalid write in CoreRE `AudioPlayerSystem.update`; no CubeGuide, SwiftUI, cube geometry or instruction audio | [Minimal source and result](overlays/regression/minimal-ar/result.json) |
| Same guarded standalone binary on iOS 26.5 | Alive/rendering after 67 seconds, then deliberately terminated | [Finite runtime control](overlays/regression/minimal-ar/ios26-result.json) |
| Standalone ARView, ordinary allocator, iOS 18.5 | Crashed on cycle 2 after the first confirmed attachment/release | [Source](overlays/regression/minimal-ar/ordinary/Probe.swift), [crash](overlays/regression/minimal-ar/ordinary/ios18-cycle2-crash.ips) |
| Plain UIView on iOS 18.5; same ARView binary on iOS 26.5 | Both completed 100 verified window-attachment and weak-release cycles | [Controlled comparison](overlays/regression/minimal-ar/ordinary-controls-result.json) |
| CubeGuide on iOS 26.5 after correcting ambiguous test queries | Three runs passed all 20 preview/Home/Resume cycles, preserving the entered sticker and missing count | [Repeated product result](overlays/regression/product-runtime-control/preview-passed/result.json) |
| First complete PR run on iOS 26.5 | 53/56 simulator tests passed; three guide tests timed out on offscreen controls. All non-simulator stages passed | [Full failed result](overlays/regression/ios26-pr/summary.json) |
| All five guide tests after adding bounded scrolling to their helper | Passed, including completion/acknowledgement/recovery; no production code change | [Focused result](overlays/regression/guide-scroll/summary.json) |

The standalone controls provide evidence of a runtime-dependent framework failure independent of CubeGuide. They do **not** establish that every original app crash shares that cause or that physical iOS 18 devices behave the same way. Minimum-OS qualification needs a working, named environment and a fresh passing run; it has not been waived.

## Separate UI-test problems resolved during the comparison

The iOS 26.5 accessibility hierarchy exposes some alert and sticker-picker actions as a Button containing another Button with the same identifier and frame. A single-element query was ambiguous even though the action was visible. Tests now select the first matching action within its alert or sheet. The [alert hierarchy](overlays/regression/product-runtime-control/query-diagnostic/hierarchy.txt) and [sticker hierarchy](overlays/regression/product-runtime-control/sticker-query-diagnostic/hierarchy.txt) preserve the observations.

The guide helper also required a control to be hittable before scrolling. A longer caption at step 7 moved acknowledgement below the viewport, as shown in the [failed test frame](overlays/regression/ios26-pr/guide-completion-failure.png). The helper now waits for existence and enablement, scrolls at most four times toward the target, and still requires hittability before tapping. Progress, replay, replacement and separate physical-confirmation assertions remain.

These changes repair test navigation. They do not claim to fix the iOS 18.5 renderer failure or qualify physical accessibility.

## Current continuation

The fresh full PR run after both test fixes completed with exit 0: all 56 simulator tests passed, zero failures or skips, with all package/storage/solver/reference stages passing. [Final summary](overlays/regression/ios26-final-pr/summary.json) and [source verification](overlays/regression/ios26-final-pr/source-verification.json) identify the qualified local checkpoint. No process from this run remains live. T07 completion artwork is next; the original iOS 18.5 failure, media, camera, device/accessibility and distribution work remain open.
