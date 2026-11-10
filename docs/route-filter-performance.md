# Route filtering and derived masks

A single global scope threshold is usually inherited by multiple routes.
Previously every enabled/begin call scanned all routes and then checked each
route's filter and min_level. Configuration publication now generates inherited
masks per log level plus a bitmap of routes with independent filters.

At call time the global threshold bound to that configuration generation is still
read; when the threshold allows the current level, its inherited mask is read and
the independent-filter bitmap is traversed. Each independent route decides
whether to join the result using its own scope rules and min_level. `level=off`
always returns an empty mask. Independent filters are not constrained by global
off, and scopes still use the original boundaries and longest-match rules.

Derived data belongs to the immutable snapshot and is generated before the gate
is published. Filter-only reload does not change routes/min_level, so it reuses
the masks with the new global threshold; full replacement generates masks from
the new routes. Old-generation pending records, readers, channel pins, and
recovery fingerprints keep the original protocol. Each generation adds 64 bytes
and no hot-path allocation, lock, or new atomic operation; the data never enters
persistent files.

## Correctness evidence

Internal comparison tests traverse 0/1/2/7/63/64 routes, all seven global
thresholds, seven event levels, and ten scopes, computing expected values with
the original per-route scan across 2,940 combinations. They also cover all 64
inherited-mask bits, the 64th independent route accepting while global is off,
and rejection of off events.

External `test-route-filters` uses real public Logger and 64 independent sinks
under sync, shared Memory async, and SPSC Memory async to check `enabled`, emit
results, JSON route_mask, and per-sink delivery counts. Tests cross filter-only
reload and complete route/min_level replacement, and verify old-snapshot
retention and channel-cache refresh. Existing configuration transactions,
predicates, old-admission stopping points, and SPSC no-shared-reader/pending-RMW
tests continue to pass.

## Same-condition measurement

`zig build bench-routes -Doptimize=ReleaseFast -j1` measures 1/8/64 routes with
all-inherited, mixed, and all-independent filters. It calls public
`Runtime.enabled` while varying level and scope; configuration setup, full
combination oracle verification, and allocation are outside the timed region,
with 10,000 calls per batch, five repetitions, and one monotonic clock pair.
Output checksums verify every decision, and the runtime allocator rejects new
allocation after setup.

Before-source was frozen independently, and application and library were both
ReleaseFast. One CPU was fixed, five process pairs alternated before/after, and
all 225 reported pairs matched on checksum, inputs, and budgets. Local median
ns/check:

| Routes | Rule shape | Before | After | Qualification |
| --- | --- | ---: | ---: | --- |
| 1 | all inherited | 25.62 | 25.60 | essentially unchanged in this small range |
| 8 | all inherited | 30.81 | 25.61 | about 17% lower locally |
| 8 | mixed | 31.23 | 25.49 | about 18% lower locally |
| 8 | all independent | 36.85 | 32.33 | about 12% lower locally |
| 64 | all inherited | 101.31 | 25.61 | cross-round spread above 10%, inconclusive |
| 64 | mixed | 127.06 | 34.79 | cross-round spread above 10%, inconclusive |
| 64 | all independent | 210.27 | 142.68 | about 32% lower locally |

This is `enabled` filtering cost and does not replace log capture, JSON encoding,
background delivery, or file I/O throughput. A separate original snapshot public
benchmark kept the Memory queue, five numeric fields, ZeroClock, sleep worker, and
written confirmation; 40 shared/attached admission and complete-log trials
completed, with 200,000 accepted=written records and pending/drop/measurement
runtime allocation all zero. Both complete performance comparisons exceeded the
10% noise threshold and were reported inconclusive, so no overall speedup is
claimed.

The scenario's min_level distribution is fixed; sparse independent filters or
level=off hits on this host cannot be generalized to arbitrary business rules or
machines.
