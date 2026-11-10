# Named field capture and context

When an ordinary logger has no attached context, fields are captured directly
into the final descriptor array. Named struct and tuple lengths are known at
comptime, and stack descriptors reserve space for the actual field count up to 64;
dynamic slices/pointers keep the 64-field budget. After success, the message,
keys, strings/bytes, and nested descriptors remain borrowed until synchronous
encoding or until asynchronous acceptance completes the copy; direct capture does
not relax lifetime rules.

Named struct member names are unique by Zig guarantee, so `fields.appendFields`
compares a new key with the existing prefix only when necessary and does not
re-compare known-distinct members of the same struct. Existing prefixes are still
fully validated, new values are checked in their original order, and attributes
share the node budget. Dynamic Field tuples/slices, arrays, and nested groups
continue to check duplicate keys, and an empty input does not skip an existing
invalid prefix.

Named members whose static type is clearly scalar now count as one node directly
instead of going through dynamic Value validation dispatch; `fromAny` still
validates supported types, and node budget advances in the original order.
`Value`, arrays/groups, and optional containers continue full recursive
validation. Existing prefix and dynamic-key inputs keep the original checks. The
capture result is not treated as a reusable proof: a clock callback may rewrite
borrowed fields, so Runtime still validates the final tree before
predicate/reservation. New shared/SPSC tests create a cycle inside a clock
callback, confirm `CyclicValue` is returned without consuming a slot, and verify
that complete JSON is written correctly after the fix.

Borrowed and owned child loggers keep the original context merge path: parent <
child < event, with existing keys retaining their position and taking the new
value. Unknown input types, 65 fields, cycle/depth/nodes/duplicate keys still fail
during capture, normal emit allocates no heap memory, and a capture failure ends
admission without reading the timestamp or reserving a queue slot.

## Verification

`zig build test-field-keys -Doptimize=ReleaseSafe -j1` runs nine independent
public tests against `std.mem.eql`, covering 65,016 short/long-key, unaligned,
same-pointer/different-length, and byte-mutation comparisons, plus 55
first-duplicate combinations and tree/depth/node error ordering. Real Linux
mmap/mprotect guards cover slice boundaries at both ends; other platforms skip
that case. The step is part of normal test/`verify-local` and exposes no private
comparator or reusable validation proof. A short-key optimization candidate was
fully withdrawn because general inputs regressed; production continues to use the
original `std` comparison.

`zig build test-capture -Doptimize=ReleaseSafe -j1` includes eight public API
tests: 0/5/10 fields, optional/bytes/float/128-bit integers, real named struct
64/65 boundaries, dynamic tuple/slice duplicates, shared/SPSC source-overwrite
snapshots, context position/precedence, zero allocation after initialization,
invalid nested input, and clock mutation after capture. New shared/SPSC parameter
regressions verify that a valid deferred array/group changed into a cycle/
duplicate by the clock returns a submit error, `capture_errors` does not grow, no
slot is reserved, admission is released, and complete JSON succeeds after the
original tree is restored. The field module also has counting tests confirming
named keys no longer perform internal key comparisons and static scalars skip
dynamic dispatch; combined node budgets and multi-error precedence still match the
original path.

A 2026-11-03 private typed-construction candidate reused scalar properties before
type erasure and reduced four complete PMU instruction groups by about 8.1%, but
default E-core throughput showed a repeatable regression, so all production
entries were withdrawn. Metadata private copies, all boundary tests, dual-topology
rechecks, failures, and negative data were retained; local instruction reductions
cannot be treated as current throughput or a cross-library ranking.

`zig build bench-capture -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5`
reports public `appendFields` and complete synchronous JSON separately. Empty
append is a no-work baseline; synchronous measurement includes fields, filter,
encoding, sink, and written confirmation, not journal producer latency. Each batch
uses one clock pair, complete JSON is consumed by a hash, and borrowed-overwrite
is a control.

Before used an independently frozen source module, and the same benchmark source
fixed the session to 1 so before/after complete JSON bytes match line by line.
All 45 reported pairs matched on checksum, output bytes, accepted/written, input
shape, iteration, and budget, with zero Runtime allocation during measurement.
Raw results and source/binary SHA-256 are no longer tracked.

Five fixed-CPU trials produced these median ns/call values:

| Operation | 5 fields before/after | 10 fields before/after |
| --- | ---: | ---: |
| appendFields, including key/value hash consumption | 53.43 / 25.42 | 174.54 / 48.71 |
| Complete synchronous JSON without context | 581.91 / 520.12 | 955.09 / 756.27 |
| Borrowed-overwrite complete synchronous JSON | 617.57 / 563.16 | 981.29 / 845.51 |

The 10-field append candidate had large variance, so a single median cannot claim
a stable improvement. Complete synchronous data proves only a narrow result for
this input and platform; it does not generalize to arbitrary payloads/thread
counts. Another real Memory-SPSC benchmark ran ten before/after trials, each
delivering 50,000 complete records with pending/drop/allocation zero, but the
overall regression tool was inconclusive because queue/scheduling noise exceeded
the threshold. No stable speedup or industry ranking is claimed for asynchronous
logging.

The current static-scalar experiment's complete-file user PMU separates scalar
capture from 64-bit bounded length accounting: scalar capture alone reduced SPSC
P4/shared P1 instructions by 2.68%/2.97%, and the combination reduced them by
3.00%/3.32%, with count spread passing the threshold. One hundred formal file
trials verified 10.1 million JSON records; throughput was entirely inconclusive
and several medians fell. SPSC p50 fell but p99 had a negative median, and another
20 long sampled trials observed the same change; all original values were
retained, and no low-tail-latency or cross-library improvement is claimed.
