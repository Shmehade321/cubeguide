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
