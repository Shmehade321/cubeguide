# T11 — Harden and qualify release build

## Current local automation

The final source passed 283 Swift package tests, 18 infrastructure tests, six table-oracle tests, ten corpus-tool tests and three reference-adapter tests. The clean PR Xcode plan then passed 66 tests with zero failures or skips on the explicitly selected iPhone 16 Pro iOS 26.5 simulator; 20 were end-to-end UI tests. A generic unsigned Release device build succeeded, bundled `phrases.json` and E01–E03, compiled the app icon catalog, and completed Xcode's shallow store validation.

The prior same-day full PR solver gate passed the 10,000-state seeded corpus, all 46,741 shallow states, eight named cases and pinned-reference comparisons, plus 33 process-kill storage cases. The app-only A01/A04/E01–E03 changes after that run do not alter CubeKit or solver resources, but this is still not a release-candidate million-state result.

## Qualification blockers

`Scripts/validate-assets.sh` now fails only for A08 and N01–N30. `Scripts/check-qualification.py release` stops because `docs/evidence/release.json` does not exist; creating passing rows without the required external evidence would be false. The one-million-state release corpus, mutation run on an exact candidate commit, 100 consecutive full physical cycles, low-storage and upgrade trials, live camera/image corpus, disconnected installed build, device latency/memory/thermal/frame measurements, iOS 18 minimum-OS renderer qualification and signed packaged-app audit remain unrun. T11 is not complete.
