# Project integration

The supplied revision 2 documents in `Documentation/` are authoritative. Planned `CubeGuide` app/project/test names map to the existing lowercase `cubeguide` names. No second app is created. The existing bundle identifier/signing settings are retained; final owner identity remains an external release input.

`Packages/CubeKit` compiles with Swift 6 language mode independently of Xcode. CubeCore has no UI or hardware dependency. App targets retain explicit main-actor isolation, while package mathematics uses immutable Sendable values. New package modules will be added with their first tested behavior, not empty placeholder implementations.

The app targets iPhone on iOS 18.0+. Mac Catalyst, Designed for iPhone on Mac, and visionOS compatibility distribution are disabled. Local observed toolchain: Xcode 27.0 (27A266a), Swift 6.4. Installed-version observation does not certify stable-channel or App Store eligibility.

## Verification commands

```sh
swift test --package-path Packages/CubeKit
python3 -m unittest discover -s Tests/Infrastructure -v
SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ./Scripts/test-pr.sh
./Scripts/validate-assets.sh
```

That UDID is the local iOS 18.5 iPhone 16 Pro simulator observed during T01. On another machine choose an explicitly inventoried available device using `xcrun simctl list devices available`; missing destinations cause failure. Qualification still requires specified narrow/wide layouts and physical target phones.

PR scripts record commit/toolchain, run the currently implemented package/infrastructure/app suites, reject failed/skipped/empty runs, and retain `.xcresult` plus summary JSON. They do not certify future unimplemented suites. As features land, corpus/mutation/device qualification is added without changing the product's acceptance thresholds. Nightly/release commands additionally require qualification evidence. The asset command intentionally fails while production assets are absent.

GitHub workflow is checked in but has not run remotely: this repository currently has no Git remote. A runner without the required runtime must be configured rather than silently using another platform. No credentials are committed.

## Solver model and tables

`CubeSolver3` owns independent cubie permutations, coordinate codecs, bounded binary parsing and an immutable resource loader. T04 adds bounded two-phase IDA* with 12/18 depth limits, admissible paired-distance heuristics, same-face pruning only within each phase, and fresh move history at the phase boundary. `CubeTableTools` and `TableGenerator` are development-only targets; the application does not depend on them.

`Scripts/verify-tables.sh` verifies the generator source against the manifest's source commit, generates into two clean directories, compares both with the packaged files, and runs the independent Python/NumPy oracle. The oracle reconstructs every move transition via facelet geometry, recomputes every distance, checks all outgoing edge distance bounds and predecessors, and verifies corruption detection. Install its pinned development requirements with `python3 -m pip install -r Tools/TableValidator/requirements.txt` when not already available. They never become an app dependency.

Runtime resources are limited to ten files with known dimensions and a bounded manifest. Complete-file SHA-256, version, path, dimensions, counts and value ranges are checked before exposing tables. Search uses the loaded immutable arrays with checked coordinate inputs. Loader cancellation is checked between bounded file operations; device cancellation latency remains a T04 qualification obligation.

## Search orchestration and qualification

`SolverService` is an actor that cancels and awaits a replaced worker before starting another. CPU work runs in a detached task, with a lock-protected cancellation token and immutable shared tables. Request identity prevents an already-computed stale answer from reaching the consumer. `SolverRuntime` uses a monotonic clock and independent CubeCore replay; only `VerifiedPlan` can become guidance. The app dependency container owns one service; manual-entry UI comes at T06.

`Scripts/test-solver.sh` runs the tier selected in `TestPlans/corpora.json`, all 46,741 shallow states, named hard/invalid fixtures, and the pinned Java differential reference. Every answer is also replayed with the independent Python geometry oracle. Corpus/result hashes, versions, raw durations and every failure are retained. The PR tier uses 10,000 unique states; nightly 100,000 with a recorded daily UTC seed; release one million. `CUBE_CORPUS_SEED` can reproduce another recorded seed. Java 11 is the reference runner default; `JAVA_HOME` may specify a compatible installed JDK, whose exact version is recorded.

Run `python3 Tools/MutationChecks/core.py` and `python3 Tools/MutationChecks/solver.py` sequentially with no concurrent Swift builds: each temporarily edits sources and restores them. Mutations count only when a discovered test produces a behavioral failure. Do not equate desktop warm benchmarks or simulator integration with the outstanding physical iPhone cold/warm benchmarks, whole-app memory or cancellation-latency gate.

## Guide persistence composition

The app dependency container links CubeSession and owns one SessionStore for `Application Support/CubeGuide/Guide`. That actor exclusively serializes writes and deletion for the directory. A storage lease belongs to a producer generation; deletion invalidates prior leases. GuideArchive validates bounded, checksummed snapshots by independent replay and action reconstruction before restore opens physical comparison. Temporary files are not confirmed records. Guide and manual-draft archives use the same bounded checksum envelope and atomic replacement implementation; one deletion lease owns both files.

The store excludes its directory from backups and requests complete file protection on iOS before writing the payload. File access failures propagate; only ENOENT means no saved guide. Simulator integration verifies the real solver/reducer/save/restore composition, not hardware encryption or locked-device behavior. The observed simulator does not expose the protection attribute; physical assertions and lock testing remain an open qualification gate. The user-facing session UI, settings and diagnostics stores remain subsequent work.

## Accepted scan observations

`CubeScan` depends only on CubeCore and Foundation. CubeSession depends on CubeScan and retains public aliases for the existing CubeColor, CenterPalette and PaletteError names; encoded center palettes keep the same representation. Callers using palette members explicitly import CubeScan under Xcode member-import visibility; CubeScan is also an explicit application package product dependency. The new immutable ScanDraft holds six canonical slots populated in F,R,B,L,U,D capture order. Each accepted face contains nine measurements, optional manual overrides, an explicit optional center name, capture metadata and the recorded correction rotation. It has no image field or completion-proof API.

CaptureMetadata describes the upright, unmirrored processing image while retaining source orientation/mirroring provenance, the explicit cube pose and a bounded sampling-version identifier. Coordinates and sizes are bounded; four corners must form a clockwise convex quadrilateral. The normalized cross-product cutoff of 1e-8 rejects numerical degeneracy; it is not a tuned camera-quality or confidence threshold. Actual frame normalization, homography, sampling, quality assessment, six-center classification, durable scan storage and camera/session adapters remain subsequent work. Synthetic observation fixtures prove these value contracts, not recognition accuracy.
