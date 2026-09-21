# T06 — Manual-entry product flow

Status: running. Base: 7bfad2b. This first increment connects Home and manual entry to the real SessionController and durable SessionStore. It does not complete T06 or the product.

## Increment 1 — Home and durable editor

Home exposes explicit manual entry, resume, replacement consent and confirmed deletion of saved cube data. Entry requires six distinct, explicitly selected center colors; the remaining 48 stickers start empty. The editor presents the canonical six-face net, named top neighbors, semantic color names/letters, per-face rotation and sticker clearing. Center cells open a separate center-assignment form. There are no inferred manufacturer defaults. Existing reducer/storage barriers govern edits and relaunch recovery.

Application composition now permits absent guide playback. Play/replay explicitly reject that missing capability without changing preview or guide progress. This allows the implemented editor to use the production controller without a no-op player. Guidance is visibly unavailable until its implementation; this is not a guidance completion claim.

Behavioral RED was observed for the missing Home entry control and for play/replay without playback (four failed assertions). All 163 session tests then passed. The first full UI target run executed and passed two tests covering centers, sticker entry, relaunch, keep/replace and deletion. Its screenshot exposed faded disabled centers. A new center-interaction test failed at the expected enabled assertion in a fresh build; center taps now open the form and retain normal swatch rendering. Empty-cell text follows the system foreground in dark appearance. Storage-failure copy avoids promising data retention when a write/deletion cannot be confirmed.

An exact-method Xcode selection returned success with zero tests; it is rejected as evidence. Another incremental run did not show the new center assertion despite recompilation. Its cause is unconfirmed. A separate fresh derived-data directory produced the expected behavioral failure (two executed, one failed). Use actual xcresult counts and executed assertion traces, not the xcodebuild success banner alone.

Local logs: Artifacts/t06-editor-ui-red.log, t06-missing-playback-red.log, t06-editor-session-green.log, t06-editor-ui-target.log, t06-center-fresh-red.log. Final regression and screenshot review are recorded below.

## Remaining exit work after increment 1

Validation/error correction, solved wording, Solve/Not now, cancellation/timeout, verified-plan display, Help, persisted settings, practice isolation, 3D preview and the other required screen states remain open. No camera, guidance/media, physical accessibility or distribution evidence is claimed. T05 remains running for camera-dependent acceptance and full lifecycle gates; its tested manual contracts support this independent UI increment.

## Increment 1 regression

The fresh focused UI run executed two tests with zero failures/skips. The retained screenshot was visually inspected: center swatches retain full color, the editor navigation title is compact, and color letters remain visible. This is one iPhone 16 Pro / iOS 18.5 simulator appearance, not dark-mode, narrow-screen, Dynamic Type or physical accessibility qualification.

After cleaning DerivedData, `SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t06-editor-pr Scripts/test-pr.sh` exited 0. All 237 package tests, 45 Python tests, 33 real host process-kill cases and eight simulator app/UI tests passed. Xcode reports zero failed, skipped or expected-failure tests. The UI execution trace includes center-form access, duplicate-center rejection, rotation, clearing, relaunch persistence, keep/replace and deletion. The unchanged solver passed 10,000 PR states, 46,741 shallow states, eight named cases and pinned-reference comparisons. All non-document source hashes match the pre-test snapshot.

Portable reports, compressed logs, source hashes and the inspected screenshot are in `t06/editor/`. Full local artifacts remain in `Artifacts/t06-editor-pr/` and the focused `.xcresult` directories. This coherent increment is verified; the remaining T06 exit work above is not implemented or waived. No public shipment is claimed.

## Increment 2 — validation and calculation screens

The editor now exposes Validate only for a complete draft outside its saving phase and offers a focused face view alongside the net. Validation uses the existing real reducer: no guessed correction or automatic solve. Invalid input has diagnostic text and Edit colors; already-solved input says “Your entered colors are solved” and persists entered-color completion through the existing save barrier. Scrambled input has explicit Solve/Not now, and calculation has elapsed time and cancellation. A verified result is identified as a checked plan, with animated guidance explicitly unavailable until T07/T08.

Initial behavioral RED: `Artifacts/t06-validation-red.log` executed one test and failed at the missing Validate control. Follow-up UI runs exposed inadequate readiness checks around menu/alert dismissal and per-cell writes; these runs are not counted as passes. One incremental rerun again omitted newly added test checks despite recompilation. Its cause remains unconfirmed; a clean build is required for the current evidence. A malformed test-helper edit caused a compile error and was corrected, not counted as behavioral RED. The current full-entry test waits for hittable/enabled controls and checks the actual saved color after every sticker.

At the initial implementation checkpoint, final regression and scrambled-input UI evidence were pending. Their completed results are recorded below. Identifiable-error highlighting, Help on resource failure and the remaining T06 exits remain open.

The synchronized solved-input UI run (`Artifacts/t06-validation-ready2.xcresult`) executed one test and passed in 293 seconds. It entered all 48 non-center stickers through the UI with a nondefault explicit palette, checked each saved color, introduced a wrong sticker, verified its count diagnostic, corrected it, saved entered-color completion, and verified that completion after process relaunch. This is not a physical solved-cube check.

The PR runner now cleans app/test build products before its Xcode qualification step and retains `xcode-clean.log`. This is a precaution against the observed omitted-assertion traces; the underlying incremental-run cause has not been established.

The focused scramble test entered the independent literal R fixture, reached the offer, chose Not now, resumed, requested the real solver and reached a verified plan. Its assertion that the solution must contain exactly one move failed: the inspected screenshot showed two moves. The contract permits a verified solution of at most 30 moves, not optimality; the UI assertion now checks that bound. This failed run is retained and is not reported as a pass or a solver defect. Home now performs the reducer's safe cancellation/comparison transition and exits it in one user tap; no action is acknowledged and alignment is not granted by that navigation.

Current screen coverage is partial: S01 has manual start/resume/replace/delete; S05 has explicit centers, net/focused editing, named colors, rotation and Validate; S06 has real classification and consent; S07 has calculation, elapsed time, cancellation and one longer retry; entered-color S11 uses durable completion. Camera/practice/Help/settings, 3D preview, identifiable-error highlighting, dedicated cancellation/timeout/resource-error UI tests and physical accessibility evidence remain open. Existing reducer tests establish cancellation/retry rules but are not substituted for those missing UI tests.

## Increment 2 regression

`SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t06-validation-pr Scripts/test-pr.sh` exited 0. All 237 Swift package tests, 45 Python tests, 33 real host process-kill cases and ten simulator tests (six app integration, four UI) passed, with zero failures/skips. The UI suite executed for 608 seconds, including both complete 48-sticker input paths. The corrected scramble test passed Solve/Not now, resume, real verified result, the 1…30 move bound and one-tap Home; the solved-input test passed invalid-count correction and persisted entered-color completion after relaunch. The unchanged solver passed 10,000 PR states, 46,741 shallow states, eight named cases and pinned-reference comparisons.

All non-document source hashes match the pre-test snapshot. Portable logs/reports, source hashes and the visually inspected verified-result screenshot are in `t06/validation/`; full local artifacts and result bundles remain under `Artifacts/t06-validation-pr/`. The displayed result correctly says two moves for the literal R fixture and does not present unavailable animation as working guidance.

Next: identifiable validation-error highlighting and dedicated calculation failure/cancellation UI qualification, then Help/settings/practice and 3D/guide integration. T06 and T05 remain running; physical/media/distribution gates remain notRun. No public shipment is claimed.

## Increment 3 — identifiable validation review

The core now derives canonical review-cell indices from the current first validation diagnostic. Counts identify the observed matching color, centers identify the inconsistent center, impossible pieces identify their actual cells, and duplicate pieces identify both observed occurrences rather than expected home locations. Global orientation/parity errors return no guessed faulty piece. The original validator and its diagnostic ordering remain unchanged.

Behavioral RED: four new core tests executed; three failed with 13 assertions against an empty implementation. The fourth confirms that valid states and nonlocalizable errors do not invent a location. All 31 core tests passed after implementation. UI marker wiring and its regression are pending.

UI behavioral RED: `Artifacts/t06-review-ui-red.log` executed the complete solved-input test and failed only at the missing “Review this sticker” value. The implementation now uses a symbol, stronger outline and accessibility value for related cells, with explanatory text that a mark does not identify a definitely wrong sticker. Marker positions are recomputed from the current draft during correction; incomplete/valid input has no markers. New-cube entry resets the transient review mode. The core duplicate tests also cover cyclic corner rotation and reversed edge observations; all 31 core tests still pass. Full regression and screenshot inspection are recorded below.

## Increment 3 regression

`SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t06-review-pr Scripts/test-pr.sh` exited 0. All 241 package tests, 45 Python tests, 33 host process-kill cases and ten simulator tests (six app integration, four UI) passed, with zero failures/skips. The new UI assertions confirm the related-sticker value, avoid guessing the missing-color position, and confirm marker removal after correction. The screenshot was visually inspected: symbols and stronger outlines are visible on the eight observed Green stickers without covering their color letters; the erroneous Blue sticker is not falsely identified as the known culprit by a count-only diagnostic. The explanatory legend remains visible.

The unchanged solver passed 10,000 PR states, 46,741 shallow states, eight named cases and pinned-reference comparisons. All non-document source hashes match the pre-test snapshot. Portable evidence is in `t06/review-markers/`; full local artifacts remain in `Artifacts/t06-review-pr/`. This is simulator rendering/accessibility-value evidence, not a physical VoiceOver, Dynamic Type or usability qualification.

Next: dedicated calculation cancellation/failure UI qualification and the remaining Help/settings/practice flow, followed by 3D/guide integration. T06 remains running; no physical/media/distribution gate is waived and no public shipment is claimed.
