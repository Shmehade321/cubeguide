# Behavioral mutation qualification

Run these tools alone, with no concurrent Swift build/test process in the same checkout. They temporarily edit production source and restore it after each test; never commit or build an app while a mutation is active.

```sh
python3 Tools/MutationChecks/core.py
python3 Tools/MutationChecks/solver.py
python3 Tools/MutationChecks/session.py Artifacts/new-session-mutation-run
```

The session output directory must be new. The runner first requires the unmodified session suite to pass, then applies each uniquely matched mutation and runs its targeted test. It records the source hash, result, test name, exit code and restoration check after each case, retaining complete output. A mutation counts as detected only when Swift Testing reports a completed, nonempty failed run with exit code one. Compiler errors, crashes, timeouts, missing discovery and surviving mutations fail qualification. Target drift also fails without editing the file. Infrastructure tests exercise these reporting and restoration rules.

The session catalog covers solver revision identity, guide/draft save identity, acknowledgement timing and multiplicity, preview versus physical progress, alignment and restoration, recovery/completion origin, scan persistence and capture identity, camera-run isolation, deletion leases, discard revision ordering, manual-fallback overrides and archive state consistency. These finite deliberate defects test the named assertions; they do not prove every possible defect is caught. Add cases with new contracts or newly discovered gaps.

The nightly script runs this session catalog after its ordinary regression finishes. Its final qualification ledger still requires the remaining corpus, table, mutation, image and lifecycle evidence; adding this command does not certify a completed nightly or release run. The full PR regression must pass again after local mutation work, with source hashes confirming that the real source was restored.
