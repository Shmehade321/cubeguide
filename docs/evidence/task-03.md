# T03 — Coordinates and reproducible tables

Status: running. Base: bb9ddec. R06/R13/R20, V04.

Implement coordinate rank/unrank with solved slice goal 494; independent cubie moves; exhaustive table transitions checked against independent facelet geometry; four exact BFS distance tables with independent recomputation; bounded/versioned/hash-checked binary loader; clean double regeneration. Coordinate abstractions may represent partial states that do not independently satisfy whole-cube parity; public solving will still accept only LegalCube.

Required table payload: 5,815,005 bytes. Six transitions: 2187×18 UInt16, 2048×18 UInt16, 495×18 UInt16, 40320×10 UInt16 twice, 24×10 UInt8. Distances: 2187×495, 2048×495, 40320×24 twice, all UInt8. No symmetry reduction or unproven pruning.

## Increment 1 — coordinates, cubies, binary format

Behavioral red then green observed for coordinate bounds and literal fixtures, cubie move/conversion/subgroup behavior, and binary encoding/corruption. Compressed red transcripts under t03/. Final full PR command with `ARTIFACT_DIR=Artifacts/t03-format-pr` and the recorded iOS 18.5 simulator exited 0: 39 Swift Testing functions (27 core + 12 solver), 15 infrastructure tests, two app/UI tests; zero skipped/failed.

Exhaustive rank/unrank checks cover 2,187 twists, 2,048 flips, 495 slice combinations, 40,320 eight-piece and 24 four-piece permutations, including lexicographic progression and fixed external fixtures. Cubie move checks compare all 18 moves at 120 evolving legal states (2,160 comparisons), with inverse and facelet conversion checks. The solver implements its own piece permutations/orientation deltas and never calls CubeCore's move function.

Table format tests cover the literal 36-byte little-endian header; 8/16-bit payload roundtrip; corrupted magic/version/ID/rows/columns/width/64-bit payload count; truncated/trailing data; hash mismatch; illegal transition entries and unresolved distance sentinel. Allocation bounds use fixed known table dimensions before copying/decoding input, never header-supplied lengths.

Ruling: Swift `package` access exposes solver model/table operations only to tooling targets in CubeKit, keeping them out of the public app API. Separate development-tool targets will generate/validate resources; the product module will not own offline BFS generation.

T03 remains running: no generated tables, independent full-entry validation, resource loader or reproducibility claim yet. One access-modifier edit accidentally marked a local helper `package`; compilation rejected it, it was corrected, and the full suite then passed. This compile failure is not behavioral TDD evidence.

## Increment 2 — original offline generator and independent validator

Small graph BFS and move-column fixtures observed red before implementation; full table composition separately observed red before its final implementation. A draft composition helper had been added before its dedicated test; it was removed, replaced by the minimal callable boundary and the behavioral failure recorded before rewriting it. No such draft was committed.

`swift test -c release --package-path Packages/CubeKit --filter allGeneratedTables`: all ten complete tables generated, no unresolved sentinel, sole zero at each correct goal, exact 5,815,005-byte payload; passed in 0.763 seconds after compilation on this runner. This is generation timing, not iPhone solving performance.

Full PR regression with `ARTIFACT_DIR=Artifacts/t03-generator-pr` exited 0: 43 package test functions (27 core, 12 solver model/format, four generation), 15 infrastructure tests, two app tests. Independent Python oracle self-checks: five passed (literal rank/distance fixtures, nonzero slice goal, unreachable graph and first/middle/last corruption detection).

The TableGenerator executable builds in Release. Full file generation, independent per-entry validation, clean double reproduction and runtime bundle loading remain outstanding. Generator/validator are test/development tooling, not product dependencies. NumPy 2.0.2 is installed on this runner and pinned in the validator requirements.

## Final local exit

T03 complete against its automated exit contract. Generated resources are packaged under `Packages/CubeKit/Sources/CubeSolver3/Resources/Tables`, with source commit `3e4b6a0` recorded in full in the manifest, generator version and complete-file hashes. Two clean generations were identical byte-for-byte; `Scripts/verify-tables.sh` additionally compares regeneration against packaged resources and checks the relevant generator/model files against that source commit.

Independent Python/NumPy validation compared every entry in six transitions and independently recomputed all four distance tables. It checked every outgoing distance edge (difference ≤1), a predecessor for each non-goal, and one unique goal. Distance maxima: twist/slice 9, flip/slice 9, corner/slice-permutation 14, edge/slice-permutation 12. Corrupting an entry in each of the ten tables was detected. Report: `t03/independent-table-validation.json`; full reproduction logs: `Artifacts/table-check.fqb7KC/`.

Generated payload is exactly 5,815,005 bytes, below the 64 MiB solver-asset budget; binary headers and manifest are additional small files. Direct Release generator timing and process memory are in `t03/generator-measurement.log`. They are development generator measurements, not phone solver/whole-app memory measurements. Python validator command reported maximum RSS 179,191,808 bytes during the initial check; its additional all-edge checks passed on rerun.

Bundled-loader tests observed behavioral RED then GREEN. Loader requires all ten known records, bounded metadata/file reads, valid source/hash syntax, known version/dimensions/paths, complete payloads and valid per-table values. Missing/corrupted/oversized/traversing/duplicate/unknown-version resources fail explicitly; cancellation propagates between file operations. No download path exists.

Final PR suite: `SIMULATOR_UDID=67DB7428-A25B-4167-8FC2-24F47A392E81 ARTIFACT_DIR=Artifacts/t03-final-pr Scripts/test-pr.sh` exited 0. 47 package test functions (27 CubeCore, 16 solver model/resources, four generation), 15 infrastructure tests, six Python oracle self-tests, two Xcode app/UI tests; no failed/skipped tests. `Scripts/verify-tables.sh` exited 0. The CI workflow now installs the pinned test-only NumPy version and runs table reproduction/independent validation, but remote CI still has not run because no remote is configured.

Remaining scope: the app has no search or user-facing solver flow yet. Phone runtime memory/cancellation/performance, physical scan/guide checks and distribution remain unrun later gates. Original production resources and test dependency provenance are recorded in docs/licenses.md.
