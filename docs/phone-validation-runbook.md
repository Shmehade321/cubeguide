# CubeGuide physical iPhone validation runbook

Use this runbook on the exact committed candidate before creating release evidence. A simulator pass does not satisfy any item below.

## Candidate and device record

Record the Git commit, Xcode build, app version/build, iPhone model, hardware identifier, iOS version/build, available storage, battery state and whether the phone is thermally nominal. Install directly from Xcode with the owner's development team; do not change the bundle identifier or signing settings in source solely to make a local run pass.

Start with a clean install, disable Wi-Fi and cellular access for the app test, and retain the Xcode device console. Repeat the persistence checks after terminating the app and after rebooting the phone.

## Required phone-validation pass

1. Launch offline and open Help, Settings and Practice. Confirm no content download or network requirement appears.
2. Enter a known legal scramble manually, preview the partially entered cube, validate it, run the real solver and complete the guide. Verify every move on the physical cube before acknowledging it. Confirm completion only after the cube is physically solved.
3. Background and foreground the app during editing, calculation, narration, animation and an acknowledgement save. Force-quit and reopen during an unfinished guide. The app must retain durable work and require a physical before/after comparison rather than silently advancing.
4. Exercise Pause, Replay, Home/Resume, Help and Settings during a guide. Disconnect headphones or Bluetooth during narration. Audio interruption must pause visual guidance and must never acknowledge a move.
5. Run the scan introduction, deny camera permission once, then enable it in Settings. Capture all six faces in portrait and landscape. Retake a face, rotate its review, move every crop corner and correct sticker colors. Current automatic thresholds are deliberately fail-closed, so manually confirm all 48 non-center stickers before acceptance.
6. During capture, rotate the phone, background the app, cover the lens, introduce glare, remove light, trigger an incoming-call/audio interruption if available and let the phone reach a serious thermal state only through normal use. Each interruption must stop or pause capture without losing accepted faces or accepting a stale frame.
7. Complete camera to review to solver to guide, then perform the verification scan. Compare the final facelets with the known physical cube state; any valid-but-wrong accepted scan is a release-blocking defect.
8. With VoiceOver enabled, complete manual entry, crop adjustment through the named Move actions, correction, guide playback and completion. Repeat at the largest accessibility text size, with Differentiate Without Color and Reduce Motion. Every essential control must remain reachable and named.
9. Disable narration, effects and haptics independently and confirm each preference persists. The N01–N30 human narration files are currently absent, so narration quality, Silent switch and route listening cannot pass until owned recordings are supplied.
10. On iOS 18, confirm manual preview, guide before/after comparison and completion use the labeled static renderer. Perform at least 100 preview/Home/Resume and scan/manual/solve/recover cycles while watching memory, thermal state and crashes. On iOS 26 or later, repeat the guide checks with the animated renderer and confirm at least 30 fps on the baseline phone.
11. Fill storage until the app cannot save, retry after freeing space, corrupt only a disposable test installation's saved record, and upgrade from a prior test build with unfinished work. The app must report uncertainty and must not claim a save, deletion or completed move that was not durable.

## Evidence rules

Record each result as structured JSON with `schemaVersion: 1`, the exact `commit`, `result: "passed"`, an ISO-8601 `executedAt`, `generatedBy`, and a physical `device` object containing `physical: true`, `model`, `osVersion` and `build`. Preserve the referenced `.xcresult`, console log, measurements and screenshots, then checksum each JSON artifact in the release ledger. Do not create a passing ledger row for a skipped, simulated or partially observed check.

Phone validation is blocked if any crash occurs, a stale callback changes state, a move/caption/render disagrees, an essential VoiceOver action is missing, the real cube differs from accepted facelets, or required evidence is incomplete.
