# T10 — Accessibility and full physical workflow

## Automated accessibility coverage

The final local PR plan at `Artifacts/final-xcode-20260921/tests.xcresult` passed 66 Xcode tests with zero failures or skips, including 20 end-to-end UI tests. The UI coverage exercises semantic labels and identifiers, non-color sticker labels, offline Help, portrait/landscape layout, the largest configured accessibility text size, and system Reduce Motion. Reduce Motion uses labeled static before/after views and does not advance physical progress until explicit acknowledgement. A04 Help illustrations expose combined accessibility labels; their six orientation pairs derive from the same CubeCore top-neighbor model used by entry and scanning.

This is simulator evidence only. VoiceOver traversal and announcements, rendered contrast, touch-target measurement on all screens, physical mute/haptic behavior, and device layouts remain unqualified.

## Computed contrast check — 22 September 2026

All four sticker-label paths (`StaticGuideView`, `CompletionArtwork`, `CubePreviewScreen`, `CubeSceneModel`) use one rule: white text on blue/unknown, black text elsewhere. WCAG ratios against the spec sRGB palette: blue/white 5.36, white/black 19.26, yellow/black 14.64, red/black 4.53, orange/black 8.56, green/black 4.60, unknown-placeholder/white ~8.5 — all ≥ 4.5:1. Red (4.53) and green (4.60) margins are thin under sRGB math; rendered color management could shift them, so on-device measurement stays open. Body text uses semantic system colors (Apple-managed).

## Required physical workflow evidence

The specified 20 novice sessions, including ten supervised children, have not occurred. No result is claimed for turn/regrip comprehension, actual mistakes and recovery, adult assistance, or the required ≥18/20 completion threshold. Every face-motion/audio combination still needs physical verification with the final human narration. T10 remains blocked on participants, physical cubes, phones and the owned narration files.
