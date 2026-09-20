# Test-only differential reference

Upstream: https://github.com/cs0x7f/min2phase
Pinned commit: `4d183b9eff8119cac72bc50ef35a7d8990740e06` (verified by detached Git checkout).

The `upstream/src` Java files and README are unmodified copies from that commit. The upstream source declares GPL-3.0-or-later; original notices are preserved, and `upstream/COPYING` contains the GNU GPL v3 text obtained from https://www.gnu.org/licenses/gpl-3.0.txt. The separate Java process adapter is also GPL-3.0-or-later. None of these sources, generated reference tables, or Java classes is linked into or bundled with the app.

Reference invocation uses total maxDepth 30, probeMax 100,000,000, probeMin 0, verbose 0. The pinned implementation retains its default phase-two cap of 12. This is a differential oracle, not a proof of the original Swift solver's 12/18 completeness contract. An upstream depth/probe failure must be recorded separately, never called invalidity of a known legal cube.

Compile with a recorded JDK, then feed one 54-letter canonical state per line. Output is state, tab, solution (or upstream error). Full actual runs and replay results are required before claiming differential coverage.
