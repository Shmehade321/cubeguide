# T01 — Foundation

Requirements: R14, R20. Suite: V17. Status: local exit passed; remote CI not run.

Predeclared acceptance: preserve existing app/scheme and signing identity; build iPhone simulator at iOS 18 minimum in Swift 6 mode; local CubeKit package compiles independently and is linked by the app; discovered tests must execute; intentional assertion failure propagates a nonzero exit through logging; zero discovered/skipped/failed required tests must not become a passing run; result artifacts survive failures; missing resources/evidence fail explicitly.

Environment observed: Xcode 27.0 (27A266a), Apple Swift 6.4, arm64 macOS 27 host. iOS 18.5, 26.5 and 27.0 simulator runtimes installed. Exact stable-toolchain qualification remains to be checked; an installed version alone is not release-channel evidence.

Initial repository contains Hello World SwiftUI app and template tests only. Existing uncommitted project change adds the four supplied documentation references; preserved in the baseline commit.

## Executed results

- Package discovery RED: `swift test --package-path Packages/CubeKit` through tee/pipefail exited 1 on intentional `Issue.record`. The unrelated canonical serialization test passed. Removed only the discovery probe; GREEN exited 0, one Swift Testing test executed. Red and green transcripts committed in `t01/`.
- Runner/result/asset/qualification behavior: callable minimal implementations produced assertion failures before implementation. Final infrastructure suite: 15 tests passed, zero failures; includes exit 42 preservation, missing/zero/skipped/failed results, expected failures, absent/empty/escaping asset files, duplicate IDs, stale/missing qualification evidence.
- `SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t01-full Scripts/test-pr.sh`: exit 0. Package one test; Xcode two tests (app package integration and actual simulator launch), zero skipped/failed/expected failures. Full local logs and `.xcresult`: `Artifacts/t01-full/`. Portable summary committed in `t01/app-summary.json`.
- Initial simulator build failed because the composition test did not respect the app's MainActor setting and did not import CubeCore. Fixed the test boundary/import. This compiler failure is not counted as behavioral TDD evidence.
- Final effective build settings confirmed iOS 18.0, Swift 6, iPhone only, Catalyst/Mac/visionOS compatibility disabled. Existing signing identity retained.
- Asset inventory command exited nonzero listing all 41 missing production assets; qualification guard exited nonzero for absent release evidence. These are expected incomplete-product gates, not passed media/release checks.
- `git diff --check`: passed. Build emitted an AppIntents metadata-extraction warning because the app has no AppIntents dependency; no app runtime warnings in result summary. No warning suppression added.

T01 local exit criteria met: integrated package, runnable simulator app/tests, explicit test plans, failure-propagating scripts, requirement inventory, production-asset entry point, and CI artifact-retention configuration. Remote CI has not executed (no Git remote configured). Full PR corpus arrives with T04; nightly/release qualification remains explicitly blocked until its required evidence exists. Nothing is shipped publicly.
