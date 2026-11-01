# Reuse prepared value measurement inside the runtime submission

Baseline `417e82e` has production `cd00f1f`. The previous shape-in-size-visitor
candidate was rejected; this change keeps shape checks independent and targets
a separate duplicate tree walk in the runtime's prepared path.

## Owning cost and change

The public Runtime submission audit holds the worker behind a live reservation
gap. A prepared event with four value nodes previously visits eight nodes:
runtime validates the final tree before predicates, then reference encoding
validates/measures the same tree after reserve. The candidate records four
visits in the same audit, with identical accepted output. The initial audit
incorrectly expected one pending slot while its live gap also occupies a slot;
that failed log remains, and the corrected audit checks both occupied slots.

No-redaction prepared submission now measures values and nested keys while
performing its existing complete-tree check before predicates. Its private
submission context carries the measured byte count only through the same
unmodified call. Canonical metadata resolution, schema shape/type/level checks,
full/drop/fallback decisions, capacity and reserve/commit reference checks
remain at their original boundaries. Dynamic message/trace/header lengths are
added after canonical metadata determines the wire shape. Wire overflow is
reported only after shape/level, so error precedence stays unchanged.

Internal reference primitives move into `core/reference_encoding.zig`, shared
by the safe public codec and runtime. Public `encodedReferenceSize` and
`encodeReference` always validate the entire tree and ignore any caller event
hint; no measured encoder or credential is exported through the public root.
The runtime's measured state is private, not taken from a caller's Binding or
Event. Header overwrites do not modify the fields/arguments that were measured.
Borrowed event storage must remain unchanged for the whole call, including
waits, as with existing inline sized submission.

Redaction modifies values and retains its independent original/final checks;
that path does not reuse the pre-rewrite byte count. Reference canonical/ready,
reserve/commit, consumer/reclaim integrity checks are not removed. CRC, record
pins, mapped layout/schema identity, output barriers and notification/scheduling
budgets remain. No heap allocation or queue/file/I/O budget is added.

## Semantic evidence

Four new owning tests cover Memory/Mmap×shared/SPSC, nested attributes and
deferred arguments. Direct runtime submission visits exactly five value nodes
for a five-node event; the independent public codec also visits exactly five.
Initialization is followed by a failing allocator, and output includes the
complete deferred message. A forged public tree_validated hint cannot bypass
runtime/public codec rejection of cyclic input. Predicate rejection still
precedes schema/level mismatch for a valid tree; complete tree errors precede
predicate. Full drop ignores schema shape as before; full sync fallback still
checks it. Available shape/level errors consume and abort the same reservation,
and oversized wire still returns dropped_oversize only at its original boundary.

The initial full-queue test attempted repeated error submissions without
waiting for their tombstones to be reclaimed and correctly observed dropped_full;
the corrected test ends/flushes each call before testing the next boundary.
Configured drop redaction and public Binding.definition tampering retain their
canonical semantics. No accepted secret bytes appear in output.

Debug/Safe/Fast related schema/reference/runtime scopes each pass64 tests.
`codec_differential.zig` independently compiles frozen baseline and candidate
codecs for4096 cases:342 exact successful payloads,3754 equal rejection errors
with untouched destination buffers. Source archives, harnesses, logs and binary
identities remain. These checks supplement existing wire/golden/recovery tests.

## Complete-workflow measurement

Formal trials use the unchanged public fullJSON harness, system wall clock and
five numeric attributes,256 slots/512-byte payloads,64KiB file buffer, default4
consumer quanta, actual portable backend and fixed CPU0/2/4/6/8/10. Every
physical record/ID/attribute/byte/hash is checked by the owning independent
file oracle. Throughput includes producer, consumer format/write, final written
flush, shutdown and cleanup; initialization/preparation and sampled producer
percentiles remain separate. No strict durable media flush is requested.

`measure.py --pmu` captures40 complete300k-record trials for prepared SPSC
Memory/Mmap P4, prepared shared Memory P1 and inline SPSC Memory P4 control.
`measure.py` captures320 complete100k-record trials, five alternating pairs for
Memory/Mmap×shared/SPSC×P1/P4×inline/schema×batch/sampled. All sources/binaries
are frozen before capture and guarded before/after each trial; local tests and
builds finish before formal measurement starts. User PMU includes setup and
excludes kernel work. All negative/slow rows, CV/spread/bootstrap and incomplete
measurements remain, and local savings do not provide a new Foundation ranking.

## Completed user-counter comparison

The40-trial PMU capture independently verifies12,040,000 physical records.
Schema SPSC Memory/Mmap instructions decrease3.992%/3.974%, shared Memory
P1 decreases4.328%; all three groups pass CV/spread and have non-overlapping
bootstrap intervals. Inline SPSC control instructions decrease0.124%.
These are whole-process user instructions, not a portable throughput guarantee;
user cycles and each complete workflow's time qualification remain independent.

## Complete initial file comparison

All320 trials independently verify32,320,000 physical JSON records.
Local qualification requires both CV/spread below10%; interval overlap still
limits the direction/size of a difference. All original slow observations remain.

| Mode/storage/P/shape | Before M/s | After M/s | Change | Qualification |
| --- | ---: | ---: | ---: | --- |
|async/memory/P1/schema|1.786|1.984|+11.12%|repeatable; intervals do not overlap|
|async/memory/P4/schema|2.030|2.004|-1.29%|inconclusive|
|async/mmap/P1/schema|1.823|1.971|+8.15%|inconclusive|
|async/mmap/P4/schema|2.007|2.027|+0.99%|repeatable; intervals overlap|
|spsc/memory/P1/schema|1.882|2.015|+7.08%|inconclusive|
|spsc/memory/P4/schema|2.211|2.218|+0.28%|repeatable; intervals overlap|
|spsc/mmap/P1/schema|2.008|2.000|-0.37%|inconclusive|
|spsc/mmap/P4/schema|2.283|2.236|-2.07%|inconclusive|
|async/memory/P1/inline control|2.243|2.291|+2.14%|repeatable; intervals overlap|
|async/memory/P4/inline control|2.195|2.203|+0.33%|inconclusive|
|async/mmap/P1/inline control|2.216|2.233|+0.77%|repeatable; intervals overlap|
|async/mmap/P4/inline control|2.266|2.204|-2.70%|repeatable; intervals overlap|
|spsc/memory/P1/inline control|2.312|2.229|-3.56%|inconclusive|
|spsc/memory/P4/inline control|2.408|2.428|+0.81%|repeatable; intervals overlap|
|spsc/mmap/P1/inline control|2.358|2.339|-0.81%|repeatable; intervals overlap|
|spsc/mmap/P4/inline control|2.437|2.434|-0.11%|repeatable; intervals overlap|

Schema shared Memory P1 has a locally qualified+11.12% median with
non-overlapping intervals. Other schema groups mostly overlap or exceed the
noise budget; SPSC Mmap P4 has a negative2.07% inconclusive median and
shared Memory P4−1.29%, also inconclusive. The ordinary shared Mmap P4 control
has−2.70% median with overlapping intervals; it is not a schema-path gain.

Call tails remain mixed. Schema shared Memory P1 p99/p99.9 median830/991ns
→742/2864ns, both inconclusive. SPSC Memory P4 p99.9 is341564→343504ns and
Mmap P4 is331835→329134ns, both inconclusive. A20-trial1M-record prepared
shared Memory P1 batch/sampled follow-up checks the apparent P1 throughput
benefit and tails; the original positive and negative results are retained.

## Million-record P1 follow-up

The20-trial1M-record prepared shared Memory P1 batch/sampled follow-up
independently verifies20,020,000 physical JSON records. Batch throughput
median1.899M→1.992M records/s (+4.887%) passes both CV/spread and has
non-overlapping median bootstrap intervals. Sampled throughput+11.028% has
large baseline spread and remains inconclusive. P50/p99 medians512/817→
444/665ns are inconclusive, while p99.9 median1017→15974ns is a negative
observation with non-overlapping intervals but high spread on both sides.
This is a material tail limitation; it is not hidden by throughput/CPU gains.
The capture is Memory P1 only and does not qualify Mmap or P4 tail performance.

The candidate is retained for repeated prepared Memory P1 throughput and
whole-process CPU work reduction, subject to final correctness/platform gates.
No uniform percentile improvement is claimed. Formal complete capture totals
380 trials and64,380,000 physical records:40 PMU,320 short file and20 long
follow-up trials. Both codec/tree audits are additional correctness diagnostics,
not throughput samples. No local builds/tests overlap formal measurement.

## Native resource observations

Runtime/Journal public object layouts, the private submission context fields
and queue/file/I/O backing budgets do not grow. No new heap allocation is
introduced; the failing allocator test covers prepared shared/SPSC Memory/Mmap
after initialization. Emitted native function stack allocations do change:
submitDestination952→984 bytes, submitSafeDestination3640→4024 bytes;
measureValues232 and writeMeasured408-byte frames are separately recorded.
These are explicit disassembly subtractions, not the full transitive stack:
register pushes, callees, inlining and recursion also matter. Source/assembly
records in resources.json retain this cost alongside CPU/throughput gains.

## Final gates

`zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all` passes
93/93 steps and556/556 Zig tests. The four new prepared tests, independent
five-mode/single-threaded/source-distribution packages, canonical/shape/route
error boundaries, actual random SIGKILL recovery, wire/schema mutation matrices,
allocation and output fault tests are included. Related Debug/Safe/Fast each
pass64 tests. No counted output format or durability boundary is weakened.

`zig build check-platforms -Doptimize=ReleaseSafe -j2 --summary all` passes
10/10 steps for nine actual object targets. Linux host execution is proven in
the composite; foreign object compilation does not establish device execution.
The final source/archive/binary hashes, completed measurements/distributions,
local throughput/CPU gains and negative tail observations are bound in
qualification.json. The broad industry-best goal remains active.

Build/reproduction uses the frozen owning sources and public harness:

```sh
zig test src/root.zig -O ReleaseSafe --test-filter 'prepared runtime measure' --test-filter 'reference' --test-filter 'schema'
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/cpp_reference/kron_reference.zig -O ReleaseFast -Mkron=src/root.zig -femit-bin=bench/evidence/2026-11-01-prepared-measure/kron-ref-after-final
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
zig build check-platforms -Doptimize=ReleaseSafe -j2 --summary all
```

The measurement scripts preserve completed destinations and every saved row;
use a fresh capture name for new runs and retain source/binary identities.
