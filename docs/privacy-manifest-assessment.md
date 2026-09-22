# Privacy manifest assessment

CubeGuide processes camera frames in memory, stores cube/session/preferences data only in its protected local Application Support directory, and contains no networking, analytics, advertising, account, or tracking code. Captured images are transient and are discarded after face review; persisted scan records contain measurements and crop metadata, not images.

The source audit found no use of Apple's listed required-reason API categories: file timestamp APIs, system boot time APIs, disk-space APIs, or preferences APIs. `PrivacyInfo.xcprivacy` therefore declares tracking disabled and empty tracking-domain, collected-data, and accessed-API arrays. Re-run this assessment whenever dependencies or persistence APIs change and inspect the archive's generated privacy report before distribution.

Apple schema references:

- https://developer.apple.com/documentation/BundleResources/privacy-manifest-files
- https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api
