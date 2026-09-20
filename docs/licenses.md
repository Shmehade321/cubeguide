# Source and resource provenance

The CubeGuide application code, original cubie-coordinate solver model, table generator, generated tables, and test-only integer-geometry fixtures in this repository were authored for this project from the written mathematical conventions. They do not contain a port of min2phase, copied upstream search tables, or downloaded production cube assets. Existing app identifiers are preserved, not asserted to be final store branding.

CubeCore currently uses Apple's Foundation and CryptoKit frameworks. SwiftUI is the existing app framework. Framework use does not establish final distribution/privacy compliance; audit the actual archive and dependencies at T12.

The independent table validator uses NumPy 2.0.2 only in development/CI. Its installed license notices (including applicable bundled-component notices) are retained in `Tools/TableValidator/NUMPY-LICENSE.txt`. NumPy is not linked into or distributed inside the iPhone application.

The test-only min2phase reference is vendored at commit `4d183b9eff8119cac72bc50ef35a7d8990740e06` under `Tools/ReferenceSolver/upstream`. Source files retain their upstream GPL-3.0-or-later notices; the unmodified README also contains MIT license text. The GPL text and per-source hashes are retained. The separate process adapter is GPL-3.0-or-later. See the reference README for acquisition, invocation and the production boundary; this Java tooling is never an application dependency. Production graphics, narration, sound effects and their ownership records remain unproduced. This file is an evolving inventory, not a completed release license audit.
