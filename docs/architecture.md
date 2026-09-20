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
