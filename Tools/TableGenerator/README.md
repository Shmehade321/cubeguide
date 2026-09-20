# Offline table generator

Implementation is the `CubeTableTools` library and `TableGenerator` executable targets in `Packages/CubeKit`. Swift package access exposes the solver's mathematical model to those tools without exposing it to application clients. The app does not depend on either tooling target.

After committing the generator/model sources, generate into two different empty directories with the same full generator source commit:

```sh
swift run -c release --package-path Packages/CubeKit TableGenerator Artifacts/tables-a FULL_GENERATOR_COMMIT
swift run -c release --package-path Packages/CubeKit TableGenerator Artifacts/tables-b FULL_GENERATOR_COMMIT
diff -rq Artifacts/tables-a Artifacts/tables-b
python3 Tools/TableValidator/validate.py Artifacts/tables-a
```

Only qualified tables belong in the app resources. Generation uses exact BFS and original cubie moves; the Python validator independently derives transitions through test-only facelet geometry and reconstructs all distances. Source commit/version/hash metadata does not substitute for that validation.
