# Named solver cases

`solver-cases.jsonl` stores canonical inputs, expected legality, and the construction of every fixture. Cases supplement the unique random and exhaustive shallow corpora; no claim of optimal solution length is made.

Superflip has solved piece permutations and corners, with all twelve edges reversed. The balanced-twist case has the first seven corners twisted clockwise and the eighth twisted twice, giving a total divisible by three. Impossible cases isolate one corner twist, one edge flip, or an unmatched edge transposition. The R snapshot is the independently reviewed literal facelet fixture, not a result produced by the Swift solver.

The manifest hashes these exact bytes. Both Swift validation/search and the pinned reference consume them; all accepted answers must replay through the independent facelet geometry oracle.
