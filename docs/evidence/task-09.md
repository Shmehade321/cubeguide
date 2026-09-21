# T09 — Guided camera and correction

## Increment 1 — deterministic image sampling and six-center classification

CubeScan now owns a bounded interleaved-sRGB image value, exact source-orientation and mirror normalization, projective mapping from a reviewed clockwise quadrilateral, and per-cell robust measurements. Each of the nine cells samples at most 40×40 points, converts tagged sRGB through the standard transfer function and D65 XYZ into CIELAB, and retains channel medians plus median CIE76 dispersion. Invalid dimensions, byte counts, crops and sampling budgets are rejected rather than clamped.

Final classification remains unavailable until all six faces and six unique center names exist. Once present, every non-overridden sticker is compared with all six center measurements. Results retain the nearest distance, nearest/second-nearest margin and explicit concerns for excessive distance, low margin, within-cell instability or inseparable centers. Manual overrides and named centers remain authoritative and concern-free. A reviewed state cannot become canonical facelets while any automatic reading needs review, and no color-count or solver legality rule recolors a measurement.

TDD RED was recorded in `/tmp/cubeguide-image-sampling-red.log`, `/tmp/cubeguide-classification-red.log` and `/tmp/cubeguide-policy-decode-red.log`; each failed on the missing behavior rather than a missing declaration. Focused GREEN passed four image-pipeline and five classification tests. The final full package command `swift test --package-path Packages/CubeKit` exited 0, including 19 CubeScan tests and the unchanged session, solver, table and core suites.

This increment establishes deterministic mechanics only. No production camera, real photo fixture, blur/highlight/focus assessment, calibrated `scan-policy.json`, held-out accuracy, live-device capture or scan UI is claimed. Thresholds cannot be frozen honestly until the specified labeled development captures exist.

## Increment 2 — final review acceptance boundary

Classifications carry the exact scan revision. SessionController accepts them only against the matching complete durable scan and center palette, after explicit confirmation, with no unresolved automatic-reading concerns. Legal scrambled scans enter the existing Solve/Not now gate and real solver path. Solved scans persist `scanVerified` completion; verification scans of a finished guide rebase the complete progress to a strictly newer revision before saving the same distinct evidence kind. Stale and uncertain results remain editable scan input.

Focused tests first failed against callable no-op acceptance and completion handlers, then passed all four cases. The full CubeKit suite passed. This is model/storage integration; it does not turn synthetic fixture observations into camera accuracy evidence.
