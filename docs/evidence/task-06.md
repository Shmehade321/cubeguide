# T06 — Manual-entry product flow

Status: running. Base: 7bfad2b. This first increment connects Home and manual entry to the real SessionController and durable SessionStore. It does not complete T06 or the product.

## Increment 1 — Home and durable editor

Home exposes explicit manual entry, resume, replacement consent and confirmed deletion of saved cube data. Entry requires six distinct, explicitly selected center colors; the remaining 48 stickers start empty. The editor presents the canonical six-face net, named top neighbors, semantic color names/letters, per-face rotation and sticker clearing. Center cells open a separate center-assignment form. There are no inferred manufacturer defaults. Existing reducer/storage barriers govern edits and relaunch recovery.

Application composition now permits absent guide playback. Play/replay explicitly reject that missing capability without changing preview or guide progress. This allows the implemented editor to use the production controller without a no-op player. Guidance is visibly unavailable until its implementation; this is not a guidance completion claim.

Behavioral RED was observed for the missing Home entry control and for play/replay without playback (four failed assertions). All 163 session tests then passed. The first full UI target run executed and passed two tests covering centers, sticker entry, relaunch, keep/replace and deletion. Its screenshot exposed faded disabled centers. A new center-interaction test failed at the expected enabled assertion in a fresh build; center taps now open the form and retain normal swatch rendering. Empty-cell text follows the system foreground in dark appearance. Storage-failure copy avoids promising data retention when a write/deletion cannot be confirmed.

An exact-method Xcode selection returned success with zero tests; it is rejected as evidence. Another incremental run did not show the new center assertion despite recompilation. Its cause is unconfirmed. A separate fresh derived-data directory produced the expected behavioral failure (two executed, one failed). Use actual xcresult counts and executed assertion traces, not the xcodebuild success banner alone.

Local logs: Artifacts/t06-editor-ui-red.log, t06-missing-playback-red.log, t06-editor-session-green.log, t06-editor-ui-target.log, t06-center-fresh-red.log. Final regression and screenshot review are recorded below.

## Remaining exit work

Validation/error correction, solved wording, Solve/Not now, cancellation/timeout, verified-plan display, Help, persisted settings, practice isolation, 3D preview and the other required screen states remain open. No camera, guidance/media, physical accessibility or distribution evidence is claimed. T05 remains running for camera-dependent acceptance and full lifecycle gates; its tested manual contracts support this independent UI increment.

## Increment 1 regression

The fresh focused UI run executed two tests with zero failures/skips. The retained screenshot was visually inspected: center swatches retain full color, the editor navigation title is compact, and color letters remain visible. This is one iPhone 16 Pro / iOS 18.5 simulator appearance, not dark-mode, narrow-screen, Dynamic Type or physical accessibility qualification.

After cleaning DerivedData, `SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t06-editor-pr Scripts/test-pr.sh` exited 0. All 237 package tests, 45 Python tests, 33 real host process-kill cases and eight simulator app/UI tests passed. Xcode reports zero failed, skipped or expected-failure tests. The UI execution trace includes center-form access, duplicate-center rejection, rotation, clearing, relaunch persistence, keep/replace and deletion. The unchanged solver passed 10,000 PR states, 46,741 shallow states, eight named cases and pinned-reference comparisons. All non-document source hashes match the pre-test snapshot.

Portable reports, compressed logs, source hashes and the inspected screenshot are in `t06/editor/`. Full local artifacts remain in `Artifacts/t06-editor-pr/` and the focused `.xcresult` directories. This coherent increment is verified; the remaining T06 exit work above is not implemented or waived. No public shipment is claimed.
