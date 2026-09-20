# Offline 3×3 Cube Guide — Product and Technical Specification

Revision 2 · 20 September 2026 · Working project name: CubeGuide

Read with [the verification plan](cube-app-verification-plan.md), [the implementation contract](cube-app-implementation-plan.md) and [the review record](cube-app-review-record.md). This revision defines the build contract; it does not certify an unbuilt product. An agent must implement all requirements and produce their evidence, not stop at a solver demonstration.

## 1. Purpose and agreed scope

Help a child or adult scan a scrambled physical 3×3 cube and solve it with clear, accurate, matching 3D instructions. Reliability takes priority over additional puzzle sizes or visual features.

Confirmed requirements:

- First release supports 3×3. 5×5 belongs to a later phase.
- Capture all six faces and preserve the actual sticker arrangement.
- Determine whether the confirmed state is solved, legally scrambled, or invalid.
- Ask whether the user wants guidance before solving a scrambled state.
- Show realistic layer rotations on a matching digital cube, one move at a time.
- All solving algorithms and required resources ship with the app. No AI integration or network dependency in the product.
- Develop behavior with failing tests first and extensive correctness verification.

Engineering decisions for this revision (explicit choices made to close the draft, not facts about user preferences):

- Native iPhone app, iOS 18.0 or later; Swift 6 language mode, SwiftUI, AVFoundation and RealityKit in non-AR mode. Build with the installed stable Xcode toolchain and record its exact version in CI. Validate API availability against the deployment target. No iPad-native, Mac or visionOS release; explicitly disable optional Mac/visionOS distribution until separately qualified.
- Standard six-color, fixed-center 3×3 cubes, including stickered and stickerless versions. Palette: white, yellow, red, orange, blue and green. Derive their face assignment from guided capture; do not assume a manufacturer's color arrangement.
- English initially; text and icons are sufficient for every essential interaction. Bundle human-recorded instruction audio with matching captions. No runtime speech synthesis or downloaded voices; production voice files are a required deliverable, not already-created assets.
- An adult may help younger children scan; usability testing includes beginning readers and adults.
- Manual move confirmation and full rescanning for recovery. Continuous physical move tracking and AR are later research work.
- Physical qualification covers iPhone 12 and iPhone SE (3rd generation), each on iOS 18.x, plus an iPhone on the current stable iOS at execution. Record exact models/builds before tests. If those OS/device combinations cannot be obtained, mark the gate blocked; do not silently replace the minimum-OS check with a simulator. Add minimum and current OS simulator coverage at 375-point and 430-point widths. These are required test targets, not tested-device claims.

Excluded from release one: other cube sizes, picture/oriented-center cubes, unusual shapes, damaged or reassembled puzzles requiring physical repair, accounts, cloud sync, analytics services, ads, and lessons that explain a human solving method. A solution guide is distinct from teaching cubing techniques.

## 2. Product requirements and acceptance criteria

| ID | Requirement | Acceptance criterion |
|---|---|---|
| R01 | Offline operation | Fresh install with all network paths disabled can scan, edit, validate, solve, animate, recover and resume. No first-run downloads or remote solver calls. |
| R02 | Complete scan | Six named face slots, nine stickers each, explicit top-edge orientation and visible progress. A duplicate capture cannot silently overwrite a different slot. |
| R03 | Correctable recognition | Each face has a confirmation screen, editable colors, rotation correction and rescan. Low-confidence readings require correction or recapture. Manual entry also works without camera access. |
| R04 | Legal-state validation | Validate dimensions, color counts, centers, piece identities, orientations and parity before classifying a scramble as solvable. Explain failures without claiming the physical cube is broken. |
| R05 | Consent and classification | An already-solved state gets a solved message. A valid scrambled state gets a Solve / Not now choice. Invalid scans go to correction. |
| R06 | Verified solution | Every displayed solution is replayed against the original state using a move engine separate from the solver implementation. Display only if the resulting state is solved. |
| R07 | Matching 3D cube | Confirmed views match the acknowledged state and pose. Demonstration previews are explicitly labeled before/expected-after states for the pending action and never silently advance the confirmed state. Match palette/layout; exact wear, logos and photographic materials are not promised. |
| R08 | Understandable moves | Highlight the entire moving layer, show a direction arrow and animate slowly. Provide replay, pause, speed control and optional local audio. Explain face turns and whole-cube reorientation separately. |
| R09 | Explicit progress | Previewing or replaying a move never advances progress. Only “I did this move” advances one step; duplicate taps do not apply a move twice. |
| R10 | Recovery and completion | “My cube looks different” starts a new scan and solution. Completion distinguishes user confirmation from camera verification of all six faces. |
| R11 | Safe resume | Save the last acknowledged step atomically. On relaunch, compare the physical cube with the saved model before continuing; offer rescan if uncertain. |
| R12 | Accessibility | Large controls, Dynamic Type, text/symbol color labels, VoiceOver descriptions and a Reduce Motion alternative. Essential actions work with audio disabled. |
| R13 | Responsive execution | Camera processing and search do not block UI. Cancellation, interruption, stale results and missing/corrupt resources have explicit outcomes. |
| R14 | TDD and release evidence | Every requirement maps to tests or a documented physical-device check. No skipped required tests, unexplained failures or placeholder implementations in a release candidate. |
| R15 | Complete screens and navigation | Implement S01–S11, their empty/error/loading states, saved preferences and abandonment rules in section 11. |
| R16 | Production visual assets | Ship all A-series assets, original app icon, light/dark treatment, readable labels and approved visual QA; no placeholder artwork. |
| R17 | Sound and haptics | Ship the exact narration/effect catalog; playback follows section 13, including mute, interruptions, VoiceOver and headphones. |
| R18 | Local-data lifecycle | Implement bounded, versioned draft/session/settings storage, deletion, protection and offline privacy content. |
| R19 | Distribution package | Produce a validated signed archive, TestFlight evidence, accurate store materials and the release checklist. Missing owner credentials/content blocks publication explicitly. |
| R20 | Handoff and maintenance | Supply build/test/release instructions, licenses, resource generators, reproducible fixtures and a versioned evidence manifest. |

## 3. User journey

1. **Start:** Select Scan or Enter colors. Explain that the user must rotate the whole cube during capture without turning individual layers.
2. **Establish orientation:** Choose a front and top face. Display a diagram identifying the top neighbor for each capture; animate how to hold the cube for the next face.
3. **Capture six faces:** Follow F, R, B, L, U, D slots using their canonical top-neighbor diagrams. Store each face's nine measurements and an editable preview. Until all centers exist, colors are provisional. After six captures, calibrate the six centers, classify all faces together and require final review. Never imply a final six-center classification exists at the first face.
4. **Review:** Show an unfolded six-face view and a rotatable 3D preview. Ask the user to confirm the match. A mathematically valid scan can still be a wrong scan; legality is not proof of recognition accuracy.
5. **Validate:** Separate incomplete input, invalid color/piece arrangement, solved state and valid scramble. Let users revisit any face.
6. **Offer help:** “Your cube is scrambled. Would you like to solve it?” Declining preserves the confirmed scan.
7. **Calculate:** Run local search, allow cancellation, verify the complete result before displaying instructions.
8. **Align:** Show the required front and top colors. Let the user rotate the physical cube to match before the first move.
9. **Guide:** Show the next layer turn, its before/after states and optional audio. Replay does not change the recorded physical state. The user acknowledges only after making the turn.
10. **Recover:** If a mistake or loss of orientation occurs, pause. A full rescan produces a new baseline and invalidates the previous remaining sequence.
11. **Finish:** When the expected model is solved, ask the user to confirm or perform a six-face verification scan. Never claim the camera checked a cube that was not scanned.

There is no generic “Back” control that silently rewinds the presumed physical cube. Browsing a previous instruction is read-only. Physical undo, if later added, needs its own inverse-move acknowledgement flow.

## 4. Architecture

Keep deterministic logic independently executable on a Mac through Swift Package Manager. The app supplies hardware, presentation and persistence adapters.

| Component | Responsibility | Must not depend on |
|---|---|---|
| CubeCore | Facelet state, moves, whole-cube orientation, serialization, legal-state validation and solution replay | Camera, SwiftUI, RealityKit, network, solver search tables |
| CubeSolver3 | Cubie-coordinate representation, local two-phase search, resource loading, bounds and cancellation | UI, camera, network |
| CubeScan | Guided frame geometry, image normalization, sticker sampling, deterministic color classification, confidence and face assembly | Solver choosing the “most convenient” recognized state |
| CubeSession | Workflow state machine, input revisions, acknowledged moves and recovery decisions | Rendering transforms as a source of truth |
| CubePresentation | 3D scene, arrows, camera viewpoint, audio and accessibility descriptions | Independent copies of cube mathematics |
| App adapters | AVFoundation capture, local storage, permissions and lifecycle integration | Remote product services |

Data flow: captured images → reviewed face observations → confirmed facelets → legality validation → solver → independent replay verification → immutable solution plan → acknowledged session steps → rendered cube.

Use immutable value types for states and moves. Concurrency boundaries pass values; mutable solver search state stays within a single job. Every job carries an input revision, so a result from an older scan cannot replace a newer session.

The 3×3 implementation should be explicit. Preserve interfaces for adding a different puzzle engine later, without claiming 3×3 cubie constraints work for 5×5. Rendering and guide presentation can be reused; larger-cube validation and solving require separate implementations and tests.

## 5. Mathematical contract

### Canonical representation

- Store 54 facelets in face order U, R, F, D, L, B, each row-major while looking directly at that face from outside the cube.
- Canonical top neighbors: U→B, R→U, F→U, D→F, L→U, B→U. Capture and rendering must implement this same convention explicitly.
- Face identity and observed color are separate. Preserve a six-entry center-color mapping for display and convert to canonical face labels for solving.
- The solver accepts the 18 outer-face moves: each of U, R, F, D, L, B with clockwise quarter-turn, half-turn and inverse quarter-turn. Clockwise is defined from outside the turned face.
- Whole-cube rotations change the reference frame; they do not scramble the cube. Represent the 24 proper cube orientations separately from moves. Reflections are not valid orientations.
- A public constructor returns either a validated state or typed validation issues. Untrusted arrays never reach search unchecked.

### Validation

Check all of the following, in a deterministic diagnostic order:

1. Exactly six faces, nine cells per face and six distinguishable center colors.
2. Exactly nine stickers of each color and one canonical center per face after normalization.
3. All eight valid corner identities and all twelve valid edge identities, each occurring exactly once. Reject impossible or mirrored corner arrangements.
4. Corner orientation sum is zero modulo three.
5. Edge orientation sum is zero modulo two.
6. Corner and edge permutation parity agree.

These are the conventional reachability constraints for a correctly represented standard 3×3 with fixed centers. A rejected scan does not identify whether the cause was recognition, orientation, sticker placement or physical assembly. Offer correction first. See [Kociemba’s cubie model](https://www.kociemba.org/math/cubielevel.htm) and [the cube-group treatment](https://kociemba.org/math/papers/rubik26.pdf).

### Solver choice

Implement an original, conventional Kociemba-style two-phase solver in Swift, with non-symmetry-reduced coordinate tables generated by a checked-in offline tool. The table/search contract is in the implementation plan. This deliberately avoids an unspecified third-party production port. [Kociemba describes the phases](https://www.kociemba.org/twophase.htm).

For differential testing only, pin [min2phase revision 4d183b9eff8119cac72bc50ef35a7d8990740e06](https://github.com/cs0x7f/min2phase/tree/4d183b9eff8119cac72bc50ef35a7d8990740e06). Its `Search.java` uses a default phase-two cap of 12 and probe limits; it is not a direct implementation of our completeness contract. Preserve its notices in test tooling, do not copy its implementation or tables into the app, and do not use a reference timeout as proof that a legal input is invalid. Any production dependency change requires a recorded design revision, provenance and license review.

- A solution need not be shortest. Prioritize correctness and predictable resource use.
- Phase-one depth up to 12 and phase-two depth up to 18 are the design bounds for the standard two-phase decomposition, yielding at most 30 face turns before UI reorientation cues. A half-turn counts as one move in this metric. These bounds are documented in [Kociemba’s algorithm details](https://www.kociemba.org/math/imptwophase.htm). Complete each phase's bounded search with admissible pruning; the first phase-one goal is sufficient because every state in that subgroup has a phase-two solution within 18. Reset move-history pruning at the boundary as specified in the implementation contract.
- A resource deadline is not an unsolvability verdict. Distinguish cancelled, timed out, invalid input, corrupt resources and solver/postcondition failure.
- Default search deadline: 10 seconds, with an explicit local retry allowing 60 seconds. Use a monotonic clock and cooperative cancellation checks at most every 1,024 expanded nodes and at each phase boundary. UI cancellation stops work within 250 ms on qualification devices. Neither deadline is evidence that all valid cubes are solved within that time. After extended timeout, retain the scan and offer manual retry or exit; record a qualification failure when a required corpus case times out.
- Before accepting any result, validate its syntax and length bounds, replay it from the original state through CubeCore, and require solved output. Never display a partial or unverified sequence.
- Bundle versioned tables with dimensions, generator version and SHA-256 hashes. Check structural integrity on load and do full reproducibility checks in CI. Corrupt/missing assets stop solving with a recoverable app error; no silent download fallback.

## 6. Camera recognition without AI

Begin with deliberate alignment inside a fixed grid. Provide four draggable face corners on the frozen frame and a deterministic homography to a 300×300 square. Sample the inner 40×40 pixels of each 100×100 cell after normalization. Use orientation correction, clipped-pixel rejection, robust CIELAB measurements and comparisons with the six center samples. No trained model is required. Image transforms, confidence policy and calibration parameters are versioned and tested; pixel dimensions here define the algorithm, not the preview's screen size.

Capture in consistent lighting. Flag blur, clipped highlights, insufficient contrast, occluded sample regions and unstable colors. Confidence thresholds must be calibrated on labeled images and frozen before held-out evaluation; do not invent certainty from color-count constraints.

Keep both semantic color identity and a calibrated display swatch. Show editable labels and a confirmation preview. If colors cannot be separated, provide rescan and complete manual entry. Counts or solver success must never silently “correct” a sticker into a guessed legal state.

Use the rear camera. Test image rotation, crop coordinates and device orientation end to end. Save only confirmed state and session metadata by default; raw frames remain transient. Test fixtures are collected separately and versioned with ground truth.

## 7. 3D and physical synchronization

Create visible cube pieces with consistent gaps, lighting and discrete sticker assignments. Derive resting positions from exact integer coordinates. During a turn, animate the selected layer as a group; after the animation, snap to exact coordinates to prevent floating-point drift.

The displayed resting state always comes from CubeCore. Animation is a presentation of a transition, not the method used to calculate the next logical state. Keep model state, view orientation, demonstrated move and acknowledged physical progress separate.

Use a virtual viewing camera so front, right and top layers are visible. Before each solver move, bring the face to be turned to the physical front using the deterministic whole-cube orientation planner specified in the implementation plan. Every required regrip has its own animation and “I’m holding it like this” acknowledgement. Then demonstrate only a front-face turn, with front/top/right color labels anchoring the pose. Regrips update pose, not puzzle state or solver-move count. Any free preview rotation returns to the instruction view before resuming guidance.

Pause safely during interruptions. If the app closes after animation but before acknowledgement, resume from the last acknowledged move and explain that the physical turn may already have been made. Offer comparison or rescan instead of automatically repeating it.

## 8. Persistence and failure handling

Persist a versioned, checksummed local session containing original confirmed state, color mapping, verified move sequence, acknowledged index, confirmed physical pose, action identity and solver/resource versions. Use atomic replacement. Revalidate and replay the saved sequence on restore; stored data is untrusted input. Durably save an acknowledgement before showing the next action. On write failure, stay paused on the current action and require a physical-state check; do not automatically repeat a turn that the user may already have performed.

| Condition | Required behavior |
|---|---|
| Camera denied/restricted/unavailable | Explain and provide manual entry. No crash or unusable start screen. |
| Poor capture or ambiguous colors | Preserve other accepted faces; request correction/recapture. |
| Physically invalid confirmed state | Explain inconsistent scan and offer review. Never start search. |
| Timeout/cancellation | Preserve confirmed input; no partial instructions or “impossible cube” message. |
| New scan while old job finishes | Discard the old result using revision identity. |
| Verification disagreement | Block guidance and record a bounded local error category and build/resource versions, excluding sticker state and camera images. |
| Backgrounding/call/thermal pressure | Pause capture and animation; cancel or suspend work safely; require alignment check on return. |
| Corrupt or newer unsupported session | Offer safe discard and fresh scan. Never guess how to decode it. |
| Double taps/replay during transition | Serialize transitions; advance at most once per acknowledged step. |

## 9. Quality and release contract

Full test coverage of all legal cube states is impractical: the standard 3×3 has 43,252,003,274,489,856,000 reachable states. [Cube20 reports the state count](https://cube20.org/). TDD is a development discipline, not a mathematical proof or a guarantee of zero bugs.

The required assurance combines mathematical review, exhaustive tests of manageable domains, independently authored move oracles, property testing, differential checks, mutation checks, physical-cube trials and runtime solution verification. See [the verification and delivery plan](cube-app-verification-plan.md).

Required release targets, chosen here as acceptance gates and to be measured rather than claimed in advance:

- Zero unverified solutions shown, invalid-state acceptances in the adversarial corpus, duplicate progress transitions, or known data-loss defects.
- All states in the one-million-state release solver corpus solve and verify within the extended 60-second budget on the benchmark runner; report hardware and timing distribution. Run the device qualification subset separately, without inferring phone performance from desktop timings.
- On each minimum-OS qualification iPhone, cold and warm solving each achieve p95 at or below 3 seconds and p99 at or below 10 seconds across the fixed 1,000-state device corpus; every case solves within the 60-second extended budget. Measure from request to verified plan, including table loading in cold runs. Report maximum, timeouts, peak memory and thermal state. A missed target blocks release or requires an explicit spec revision; do not silently relax it.
- Solver assets at most 64 MiB uncompressed and whole-app peak memory at most 250 MiB in qualification scenarios. These are design budgets to validate early.
- At least 190 of the 200 held-out, ordinary-lighting six-face scan sessions produce the exact state before manual correction; low-confidence/incomplete output counts as a failure for this metric. All 200 must become correct through the review/correction path. Report wrong confident readings, attempts and results by lighting, cube finish and device; stress images have a separate reject/recovery evaluation. This finite-corpus gate does not promise error-free recognition in arbitrary lighting.
- At least 18 of 20 representative novice usability sessions finish correctly without an engineer intervening; include at least ten sessions with children using appropriate adult supervision. Recovery may be used. Report failed sessions rather than excluding them.
- Fresh-install offline and physical-device checks pass on all qualification devices. No critical/high unresolved correctness defects or skipped required gates.

These sample sizes and thresholds are acceptance criteria, not observed results or statistical guarantees for every user. A legally valid but misrecognized state can pass the solver verifier; user review remains necessary.

## 10. Delivery sequence

1. Use this revision and its companion implementation/verification contracts as the build baseline; log deliberate scope changes.
2. Qualify the platform baseline, resource budgets and test infrastructure.
3. Build and verify CubeCore and CubeSolver3 before connecting a camera or 3D guide.
4. Deliver a manual-entry, offline solver flow with full verification.
5. Add matching 3D guidance and acknowledged progress/recovery.
6. Add camera scanning and image-corpus evaluation.
7. Complete accessibility, audio, visual assets, interruptions, persistence, physical trials, store materials and release evidence.

Follow the companion implementation plan through distribution readiness; do not treat a working manual-entry prototype as the completed product. No product code, production media or signed app has been created by this document review.

## 11. Screen inventory, layout and navigation

All screens have accessible titles and stable test identifiers. Respect safe areas, support portrait and both landscape orientations and preserve session state during rotation. At accessibility text sizes, controls scroll instead of clipping and the 3D area may shrink. Keep essential actions reachable at a 375-point-wide portrait viewport. Phone-camera rotation changes image transforms, never canonical cube orientation.

| Screen | Required content and actions | Empty, error and exit behavior |
|---|---|---|
| S01 Home | Scan cube; Enter colors; Resume when a draft/session exists; Practice with a labeled example; Help; Settings | Starting another cube requires Keep current / Replace current if work exists. No fabricated history or account screen. |
| S02 Scan introduction | Three illustrated steps: hold the whole cube; show six faces without layer turns; review colors. Camera permission is requested only after Start scanning. | Denied/restricted camera offers Enter colors and a user-triggered route to system Settings. No repeated permission requests. |
| S03 Capture | Current slot/top neighbor, six-slot progress, viewfinder grid, capture button and lighting help | No camera stream while backgrounded or on unrelated screens. Frozen-frame failures retain prior face measurements. |
| S04 Face review | Frozen face, draggable corners, nine recognized cells, editable color labels, rotate preview 90°, Accept, Retake | Before all centers exist, label readings provisional. A center change invalidates classification of all dependent stickers; preserve manual overrides and flag them for re-review. |
| S05 Manual/review editor | Six-face net, 3D preview, selected cell row/column/face, six named palette buttons, rotate face, Validate | Manual mode begins with six explicit center assignments and empty other cells. Do not silently pre-fill a solved cube. Validation errors highlight affected cells/pieces where identifiable. |
| S06 Validation/offer | Solved, inconsistent, or scrambled result; Solve / Not now | Inconsistent → edit. Solved → completion labeled “Your entered colors are solved” for manual input. Not now → saved Home. |
| S07 Calculating | Indeterminate progress, elapsed time, Cancel | No fictional percentage. After timeout offer Try longer (once per request), Edit scan, Home. Corrupt bundled resources offer Restart app and local Help; never prescribe a download as necessary for offline use. |
| S08 Hold and guide | Front/top/right labels, regrip or turn animation, captions, Play/Replay, Pause, step count, acknowledgement, “My cube looks different” | Acknowledgement disabled during animation and persistence. No autoplay progression. Pause/Home retains last durable action. Free orbit is review-only and restores the guide viewpoint. |
| S09 Recovery/resume | Saved before-state and after-state for the potentially performed action; “Matches before”, “Matches after”, “Not sure—scan again” | Matching after can acknowledge exactly the pending action after saving; matching before replays it. Never offer these for an arbitrary unknown scramble. For partial regrips ask to realign to the last confirmed pose or rescan. |
| S10 Completion | Expected solved state; “Yes, my cube is solved”; “Check with camera”; “Still different”; Start another | Camera verification is a separate six-face scan with its own validity checks. A non-solved valid scan offers a new solution; an invalid scan returns to review. User confirmation and scan result have distinct text. |
| S11 Settings/Help/About | Narration, effects, haptics; speed; Show color labels; how to scan/turn; supported cubes; offline privacy; licenses; Delete local data; version/build | Deletion confirms scope and returns Home. Help works offline. Missing network never blocks help/privacy. External support site is optional and deliberately user-opened. |

Practice uses one fixed documented scramble `R U R' U' F2` created from a solved cube by the verified engine, clearly labeled “Practice example—not your scanned cube”. No practice state can be mistaken for a captured or physically verified cube. Provide an Exit practice action and retain the user's real session separately.

## 12. Visual and asset contract

Use a restrained, readable interface with the cube as the largest element on guidance screens. Standard system font with semantic text styles; system backgrounds and label colors adapt to light/dark mode. Buttons have at least 44×44-point targets. Body text meets a 4.5:1 contrast target; meaningful graphics/control boundaries meet 3:1. Independently check contrast after rendered color management, including custom swatches.

Display palette defaults (sRGB): white `#F5F5F5`, yellow `#F8D62B`, red `#D83832`, orange `#F28C28`, blue `#246AC2`, green `#27864B`. Captured swatches may adjust the cube preview, but selected-cell controls use the named palette and contrast-appropriate text. Use W/Y/R/O/B/G labels plus full accessibility names, especially R versus O; never encode an instruction only by color. Labels are on by default and cannot be disabled while Differentiate Without Color is enabled.

| Asset ID | Required deliverable | Acceptance |
|---|---|---|
| A01 | Original app icon: simple three-face cube mark, no text or third-party logos | Editable vector source and complete Xcode icon asset for supported OS appearances; legible at small sizes, no template icon, validated in installed app and archive. |
| A02 | Procedural 3D cube | 26 visible cubies, 54 face stickers, small bevels/gaps, neutral studio light, no remote meshes/textures. Distinct inner/outer layer surfaces during turns. |
| A03 | Turn/regrip overlays | Procedural arcs/arrows and whole-cube outline; turn highlights one layer, regrip highlights the whole cube. Arrow must remain visible in light/dark modes. |
| A04 | Onboarding/help diagrams | Three original vector/3D illustrations plus six top-neighbor diagrams derived from the orientation model; captions match narration. |
| A05 | Control icons | System symbols for camera, replay, pause, sound, settings, help, check and warning, always accompanied by text/accessibility labels; verify symbols exist on iOS 18 and provide a bundled vector fallback if needed. |
| A06 | Scan/editor graphics | Grid, crop handles, face-slot badges, focus/quality hints, color-chip selection and validation highlights; no color-only error markers. |
| A07 | Completion graphic | Reuse the solved 3D cube plus a static checkmark. One subtle transition; no confetti, flashing or endless loop. |
| A08 | Store screenshots | Real release-build screenshots for all required device slots, with accurate English captions; no mocked functionality or unfinished screens. |

Keep editable artwork/source generators and asset provenance/license records in the repository. Every referenced image, symbol fallback and audio file must be present in the installed bundle. AI-generated graphics/audio are not required for this product. There is no background music or downloaded theme pack.

Animation durations: quarter-turn 1.2 s, half-turn 1.8 s, whole-cube quarter regrip 1.2 s at normal speed. Slow doubles durations; Fast halves them. Onboarding illustrations always demonstrate slowly; the guide preference defaults to Normal and never overwrites a user's selection. Hold the before-state for at least 0.5 s; show the explicitly labeled expected after-state until acknowledgement. Reduce Motion replaces rotation with labeled before/after views and a static direction diagram. Tap acknowledgement only changes progress; it does not replay the animation.

QA captures every screen in light/dark, normal/largest Dynamic Type, portrait/landscape, and both narrow/wide layouts. Pixel snapshots complement geometric assertions; platform-specific anti-aliasing differences need reviewed baselines, never automatic blanket acceptance.

## 13. Narration, sound and haptics

The app uses a bundled human voice and captions from the same versioned phrase manifest. Voice recording is required production work; the agent must obtain an owned/licensed recording, not silently substitute online synthesis. Caption-only operation is a fallback for an unexpected audio failure, not a waiver of missing release assets.

Required phrase IDs and exact English scripts:

| IDs | Scripts |
|---|---|
| N01–N03 | “Turn the front face clockwise one quarter turn.” / “Turn the front face counterclockwise one quarter turn.” / “Turn the front face halfway around.” |
| N04–N09 | “Turn the whole cube to the left.” / “Turn the whole cube to the right.” / “Bring the top face toward you.” / “Bring the bottom face toward you.” / “Roll the whole cube clockwise.” / “Roll the whole cube counterclockwise.” |
| N10–N15 | “White.” / “Yellow.” / “Red.” / “Orange.” / “Blue.” / “Green.” |
| N16–N18 | “Front.” / “Top.” / “Right.” |
| N19 | “Rotate the whole cube. Do not turn a layer while scanning.” |
| N20 | “Fit the face inside the grid, then take a picture.” |
| N21 | “Check every color. Tap a square to change it.” |
| N22 | “The colors need another check. Review the highlighted squares.” |
| N23 | “Would you like help solving this cube?” |
| N24 | “Match how you are holding the cube to the picture.” |
| N25 | “Tap when you have finished this move.” |
| N26 | “If your cube looks different, pause and scan it again.” |
| N27 | “The guide is finished. Check that your cube is solved.” |
| N28 | “All six scanned faces are solved.” |
| N29 | “Solving is taking longer. You can try again.” |
| N30 | “Your entered colors are solved.” |

Only use N28 after a successful complete camera verification. Combine N16–N18 with color names to describe pose; label composites in the phrase manifest so a test can check ordering. N04–N09 must correspond exactly to the pose operations in the implementation contract; test listening plus physical movement. Supply mono 44.1 kHz PCM masters and bundled AAC/M4A outputs, matched loudness (target −18 LUFS integrated for complete phrases), no clipping, true peak at most −1 dBTP and no accidental long silence. Review short color tokens by listening rather than trusting loudness meters alone.

Optional effects are still bundled: E01 gentle acceptance tick (≤150 ms), E02 correction cue (≤250 ms), E03 completion chime (≤800 ms). Own/license the sources or synthesize these simple non-speech tones procedurally during asset generation. Never use an alarming failure buzzer. Haptics: one light impact on capture/acknowledgement, one warning notification on a rejected action and one success notification after confirmed completion; unsupported hardware degrades silently.

- Defaults: narration on, effects off, haptics on. Persist each independently; system volume remains authoritative. Do not play Home-screen speech automatically.
- Start one instruction on explicit Play or entry after an acknowledged action. Narration begins before the animated turn; wait for the turn phrase to finish, then animate. Replay cancels the previous utterance/animation and resets only the preview to the same action's before-state.
- Configure an ambient audio session so sound respects the Silent switch and can coexist with other audio. See [Apple’s ambient category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient). No microphone permission or background-audio mode.
- Pause stops narration and animation. Calls, Siri, app backgrounding, route loss and headphones disconnect stop playback; resumption requires explicit Play. Do not auto-transfer private headphone narration to the speaker.
- With VoiceOver active, suppress recorded auto-narration and expose the same instructions through accessible labels/announcements; do not speak over VoiceOver. Captions stay visible with sound off. Respect system haptic settings and avoid repeated feedback on rejected double taps.
- Pause mid-turn can resume the same preview on Play; backgrounding cancels the preview to its before-state and opens S09 before physical progress resumes. Playback failures cannot acknowledge a move.

## 14. Storage, privacy and operational edges

Store one real draft and one real active session; practice is ephemeral. A draft stores accepted face measurements/colors/corners and capture-pose metadata, not raw images. Frozen images live only until leaving that review screen; after relaunch, recapture is required to adjust image corners, but confirmed colors remain editable. Warn before restarting six-face capture if the physical cube may have changed between sessions.

Use an Application Support subdirectory excluded from backups for cube drafts/session/diagnostics. Apply iOS file protection to stored cube data and fail safely if locked. Settings contain only preferences and may use local defaults storage; audit any required-reason API use. No Photos writes, account, cloud container, advertising ID, tracking, remote logs, or developer analytics SDK. No camera data is sent off device. “Delete local data” cancels work and deletes drafts, session, diagnostics and preferences, then recreates documented defaults.

Cap a draft/session file at 256 KiB, a stored plan at 30 solver moves, diagnostic storage at the most recent 20 records and 1 MiB total. Diagnostic records contain only error category, build/resource versions and timing by default; no sticker state or photos. A developer test build may attach explicit fixture IDs. Release builds do not export diagnostics automatically. A checksum detects accidental corruption, not hostile tampering; all parsed values still require bounds and legality checks.

Test low disk space, locked files, malformed JSON, unsupported schema, asset load failure, app upgrades, interrupted atomic replacement and recovered temporary files. Version 1 rejects unknown schemas without overwriting them until the user confirms discard. Updates that change schemas need explicit migration tests; no automatic reset of user progress.

Pause live capture if the phone rotates while a frame is being frozen, transform from the recorded frame orientation and ignore stale frames. Reject camera interruption/missing lens/focus failure without clearing completed faces. The algorithm may miss a layer turn made between captures; final legality and user review reduce but cannot eliminate this risk. Do not advertise automatic wrong-turn detection.

Keep the screen awake only during an active capture or explicit guide playback; restore the normal idle timer on pause, background or exit. During severe thermal pressure cancel search and pause capture with an explanation; retry needs a user action. No persistent battery drain from a hidden camera or animation loop.

## 15. Shipping and ownership boundary

Required distribution work is part of the product. Complete the M7 checklist in the implementation plan: signed release archive, clean install and upgrade tests, TestFlight qualification, icon/screenshots, metadata, support and privacy pages, dependency/asset notices, encryption and privacy declarations, and App Review notes. Apple's current [submission process](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app) governs the actual upload/review; check current requirements again at release.

Include an offline privacy page describing the actual camera/local-storage behavior, and owner-controlled public support/privacy URLs for store metadata. Audit the archive and dependencies before declaring data collection. Assess applicable `PrivacyInfo.xcprivacy` entries and required-reason APIs from actual usage; do not copy generic reasons or infer “no manifest needed” from offline operation. See [Apple’s privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [App Store privacy declarations](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

External inputs that an agent must obtain rather than invent:

| Input | Owner / point when required | Effect if absent |
|---|---|---|
| Repository location and existing Xcode project identity | User, before integrating code | Work can be specified here; repository edits cannot target an invented checkout. Preserve an existing product/scheme name through a documented mapping. |
| Final public name, bundle ID, signing team and developer-account role | Account owner, before signing/distribution | Local engine/simulator development can proceed; signed delivery blocked. CubeGuide remains an internal working name. |
| Intended store audience/Kids category, countries and price | Product/account owner, before store submission | No automatic category or price choice. Complete the actual age-rating questionnaire. Do not infer a rating from “children can use it”. |
| Owned/licensed narration and any commissioned artwork | Implementer obtains rights from owner/creator before media gate | Missing files/rights block release; a media specification is not a finished asset. |
| Privacy/support URLs, public contact and required store declarations | Account owner before submission | Agent can draft content; cannot fabricate identity, contact details or legal attestations. |
| Physical test hardware, representative cubes and supervised participants | Product owner/test team before qualification | Device/camera/usability evidence stays blocked, never replaced by a simulator claim. |
| Store submission and public-release authorization | Account owner at distribution | Packaging is authorized by implementation scope; uploading/publishing needs explicit authorization unless already given. |

The offline implementation contains no purchases, outbound links in the solving flow or personal-data entry. If the owner selects Kids category, implement and test required parental gates around external links/actions and evaluate the relevant category requirements before submission. Do not assert compliance from this document alone. See [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [age-rating setup](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating).

An agent following this pack must report separately: specification reviewed; code implemented; automated checks passed; physical/media checks passed; distribution package ready; submitted; approved; publicly released. No document, test suite or agent can guarantee App Review approval or prove all future defects absent.
