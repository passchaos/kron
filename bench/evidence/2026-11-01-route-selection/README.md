# Precomputed inherited route selection

Every immutable configuration now holds seven level masks for inherited routes
and one mask of independent route filters. Derived data occupies 64 bytes per
version and is rebuilt before publication. Global reload still chooses the
effective threshold at submission. Independent scope filters still override it,
and full configuration replacement generates new masks while old pins retain
the old version. No wire format or recovery identity changes.

Correctness checks include an independent scan across 2,940 combinations of
route count, configured/event levels and scope. Public 64-route tests verify
enabled, emit, each sink's delivery count and JSON route_mask across all three
submission modes, filter reload and route/min_level replacement. They include
the most significant route bit and global-off/independent-filter acceptance.

`before-source.tar.gz` freezes the original production source and both public
benchmarks. `provenance.json` records source/binary hashes and compiler flags on
both application and library modules. The root benchmark is available through:

```sh
zig build bench-routes -Doptimize=ReleaseFast -j1
zig build test-route-filters -Doptimize=ReleaseSafe -j1
```

Five enabled-benchmark process pairs alternate before/after order on the same
CPU. Every process emits 45 rows covering 1/8/64 routes, inherited/mixed/all
independent filters and five repetitions. All 225 paired rows preserve exact
decision checksum and budgets. `enabled-comparison.json` records per-process
medians and dispersion. One inherited route stays near 25.6 ns/check; eight
routes show about 12–18% lower cost in this local corpus. Some 64-route cases
have spread above the 10% noise limit and remain inconclusive.

The full snapshot benchmark also runs with fixed memory storage, five numeric
fields, ZeroClock, sleep worker, 256 queue slots and written acknowledgment.
Forty trials across before/after/shared/attached complete 200,000 written events,
with accepted=written and pending/drop/measurement runtime allocation=0. Both
complete performance comparisons remain inconclusive, including their p99
measurements. Enabled-only cost does not establish full logging throughput.

Sources, raw reports, failure limits and qualification are separate from any
industry ranking. The test workload's min_level and scope distribution must not
be generalized to arbitrary application rules or target hardware.

Final ReleaseFast `verify-local` passes 75/75 build steps and 468/468 Zig tests,
plus Python, compile-fail, differential, package and crash gates. The final
ReleaseSafe platform gate emits all nine target objects and passes the public
route-filter test. `verify-fast.log`, `platforms-safe.log` and
`qualification.json` retain these results and exact source/evidence identities.
