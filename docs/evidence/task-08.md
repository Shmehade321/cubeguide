# T08 — Guidance, audio and haptics

## Increment 1 — phrase identity and playback sequencing

The app now has one exact N01–N30 phrase catalog and a bundled versioned `phrases.json` manifest covering those 30 narration IDs and E01–E03 effect identities. Guide captions and narration lookup consume the same operation mapping, so the six whole-cube directions and three front-turn directions cannot diverge silently.

`AudioCoordinator` uses an ambient, mixed AVAudioSession; suppresses recorded narration while VoiceOver is active; and falls back immediately to the visible caption if an asset cannot be opened. For enabled narration, `GuidePresentation` waits for the phrase to finish before starting either animated or Reduce Motion playback. Pause, stop, replacement, phone/Siri interruption and loss of a previous audio route invalidate pending narration callbacks. A stale callback cannot start the animation or advance durable progress. Playback completion still only finishes the preview; acknowledgement remains a separate user event.

Light haptics are connected to accepted captures and guide acknowledgements, warnings to rejected user actions, and success to explicit solved confirmation, all behind the persisted Haptics preference. Unsupported devices rely on UIKit's silent degradation.

Focused tests verify all nine action-to-phrase identities, exact catalog uniqueness, manifest/caption equality, narration-before-animation ordering, pause invalidation and explicit replay. All app unit tests and generic iOS compilation pass.

E01–E03 are now reproducibly generated original non-speech tones with editable mono 44.1 kHz PCM masters and bundled AAC outputs. Their durations are 120 ms, 200 ms and 720 ms, within the specified maxima; unit tests open each bundled file and verify format and duration. Enabled effects play the acceptance, correction and completion cues through the ambient mixed audio session.

The N01–N30 human recordings and their editable licensed masters are not present. Human listening, loudness/true-peak review, Silent-switch, Bluetooth/headphone and physical-direction qualification therefore remain blocking T08 work and this task is not complete.

## Increment 2 — pose narration and interruption ownership

Every new action now narrates the exact front, top and right pose colors before its turn/regrip phrase, using the same immutable action pose and palette that drive the renderer. The phrase manifest declares this composition explicitly. Phone-call and lost-route interruptions stop narration and send Pause through the session reducer, so visual playback, captions and durable progress cannot continue independently. Tests prove phrase order, stale-callback rejection and reducer/animation pause together. Human N01–N30 media and physical listening remain open.
