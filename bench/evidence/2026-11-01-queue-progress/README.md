# SPSC queue-local space notifications

Baseline `b011a45` retains production `e8bd353` and its current complete
Foundation comparison. The preceding cross-queue scheduling and direct-buffer
callback experiments were rejected; this candidate keeps the original scheduling,
checked delivery-window and producer service budgets unchanged.

## Measured waiting cost

A temporary copy of the public fullJSON harness wraps only futexWaitUncancelable,
using producer-local counters and that producer's own journal written target.
Each producer wait records whether its own written target changed across the
call. The owning independent file oracle verifies every physical record.
The diagnostic includes warmup and modifies timing; it is operation-count
evidence, not wall-time qualification. No producer trace/sampling instrumentation
is added to production or the public benchmark. The exact before/after temporary
harnesses are archived here.

Before12 and after12 diagnostic trials each verify1,212,000 physical records:
Memory/Mmap×shared/SPSC P4, three repetitions,100k measured+1k warmup. Baseline
SPSC Memory wait calls1220–1526, unchanged-written returns832–1137; Mmap wait
calls1369–1448, unchanged returns982–1060. After, every SPSC group has388 waits
and0 unchanged-written returns. Shared groups remain on their original path.
Unchanged target includes immediate epoch mismatch and possible spurious return;
it does not prove actual syscall sleep, wake cause or that all calls were wasted.

## Candidate protocol

SPSC producers observe a process-local queue space epoch before reserve. Only
the Full/block path registers its one-owner waiter, checks worker error/closing,
then waits on that observed epoch. Registration unwinds on return/error/retry.
Consumer tombstone/checked-window completion publishes that queue's epoch,
conditionally waking its waiter. The global progress epoch still wakes control
flush/shutdown waits; ordinary shared producers keep the global wait protocol.

Worker exit/error and runtime close broadcast to all stable SPSC queue epochs,
including queues whose own records made no progress. Sequentially consistent
queue epoch/waiter operations ensure either the waiter is visible to the wake or
the expected epoch has changed before futex checks it. Notification does not
replace written/free targets or certify output. No per-record CRC, pin, output
barrier, journal layout, queue/file budget, scheduler quantum or media durability
protocol changes. One64-byte aligned process-local control line is added per
journal; exact native type sizes are reported separately.

## Concurrency evidence

The owning tests stall an actual full SPSC producer immediately before entering
its real futex syscall. Three completed shared-queue records do not change or
notify that SPSC epoch. Concurrent shutdown does change/notify it, and only then
allowing the syscall confirms the producer returns rejected_closing without a
lost wake. A separate owner aborts manual reservations at that boundary and
observes reclaim/written progress through u32 epoch wrap and accepted output.
Another test triggers worker error in a different shared journal and confirms
the blocked SPSC producer gets the original write error even before it enters
the syscall. Memory/Mmap variants retain their exact accepted/written states.

Existing external public-module tests observe real Memory/Mmap full-SPSC futex
waits during shutdown and worker failure. Their observer target is updated to
the actual SPSC epoch; shared observer targets remain global. Directed
Debug/Safe/Fast each pass25 tests; external SPSC failure/shutdown each pass2.
Earlier subset logs are retained with their original scope, and test observer
targets use atomic addresses to avoid introducing a test-only data race.

## Uninstrumented qualification

Frozen original public harnesses use complete JSON, system clock/five attributes,
256 slots/512-byte payloads,64KiB file buffer, default4 consumer quanta and fixed
CPU0/2/4/6/8/10. Actual portable backend and all output counts/hashes are checked.
Full producer/consumer/written flush/shutdown/cleanup throughput is reported,
with init/preparation and independent sampled p50/p99/p99.9 separate. No durable
media flush is requested. Source/binary hashes guard every successful row.

`measure.py --pmu` runs40 complete300k-record trials for SPSC Memory/Mmap inline,
SPSC Memory schema and shared Memory inline P4 control. `measure.py` runs320
complete100k-record trials for Memory/Mmap×shared/SPSC×P1/P4×inline/schema and
batch/sampled, five alternating pairs. User PMU includes setup and excludes
kernel work. Each metric preserves all slow results, CV/spread/bootstrap and
qualification limits; diagnostic counter reductions are not substituted for
actual complete-file performance or new Foundation/io_uring rankings.

The completed40-trial uninstrumented PMU capture independently verifies
12,040,000 physical records. Four user instruction medians change by+0.06%
to+0.09%; two interval pairs do not overlap despite that small difference.
Throughput medians are+1.07%/+2.64% for SPSC Memory/Mmap inline and+1.94%
for SPSC Memory schema, with overlapping intervals. Shared Memory control
has+3.26% median and is inconclusive. These counter results do not qualify
a stable end-to-end speed improvement; the complete file/tail capture remains
the owning evidence for that question.

## Complete first uninstrumented workflow

The320-trial file capture independently verifies32,320,000 physical JSON
records. All accepted/written/drop/pending and backend/resource checks pass.
Most performance metrics are inconclusive; all slow samples remain.

| Mode/storage/P/schema | Before M/s | After M/s | Change | Qualification |
| --- | ---: | ---: | ---: | --- |
|async/memory/P1/schema|1.869|1.876|+0.41%|inconclusive|
|async/memory/P4/schema|1.980|2.037|+2.85%|inconclusive|
|async/mmap/P1/schema|1.840|1.909|+3.77%|repeatable, intervals do not overlap|
|async/mmap/P4/schema|1.996|2.024|+1.41%|inconclusive|
|spsc/memory/P1/schema|1.998|2.005|+0.38%|inconclusive|
|spsc/memory/P4/schema|2.075|2.222|+7.08%|inconclusive|
|spsc/mmap/P1/schema|1.989|2.017|+1.44%|inconclusive|
|spsc/mmap/P4/schema|2.170|2.238|+3.10%|inconclusive|
|async/memory/P1/inline|2.248|2.315|+2.98%|repeatable, intervals overlap|
|async/memory/P4/inline|2.227|2.246|+0.88%|repeatable, intervals overlap|
|async/mmap/P1/inline|2.312|2.315|+0.10%|repeatable, intervals overlap|
|async/mmap/P4/inline|2.232|2.233|+0.02%|repeatable, intervals overlap|
|spsc/memory/P1/inline|2.396|2.156|-10.01%|inconclusive|
|spsc/memory/P4/inline|2.390|2.449|+2.48%|inconclusive|
|spsc/mmap/P1/inline|2.352|2.390|+1.61%|inconclusive|
|spsc/mmap/P4/inline|2.355|2.427|+3.06%|inconclusive|

SPSC Memory inline P1 has a negative10.01% median with both sides beyond
the spread budget and overlapping intervals. A separate40-trial1M-record
P1/P4 Memory inline batch/sampled capture rechecks this path and the tails.
The unaffected shared schema Mmap P1 has a locally repeatable+3.77% median
with no interval overlap, so improved medians cannot all be assigned to the
new SPSC notification mechanism. Its shared control uses the old waiter path.

SPSC Memory inline P4 p99/p99.9 medians661/344313→562/342833ns, both
inconclusive. Schema Memory p99.9 median345083→336891ns is repeatable but
intervals overlap. Mmap inline p99 rises575→618ns and p99.9 is349256→347416ns,
inconclusive. These data do not establish that the extreme saturated tail was
removed, despite a large diagnostic reduction in repeated futex calls.

## Million-record follow-up

The40-trial1M-record Memory inline SPSC P1/P4 batch/sampled follow-up
independently verifies40,040,000 physical records. P1 batch throughput median
2.277M→2.329M records/s (+2.26%), both CV/spread pass but intervals overlap;
its short-workflow negative10.01% median is not reproduced here. P4 batch
median+3.64% remains inconclusive. Every slow P1 sampled/P4 batch value remains.

P4 sampled producer p99.9 median366312→340708ns (−6.990%) is locally
repeatable: before/after spread2.80%/1.76%, and bootstrap median intervals do
not overlap. P50/p99 medians270/551→269/559ns are inconclusive, so no
universal percentile improvement is claimed. The p99.9 remains about340µs;
queue-local notifications do not remove the underlying service/OS latency.
Mmap and other groups' tail gains remain unqualified by this Memory-only long
capture. This result justifies retaining the limited candidate only after
full lifecycle/concurrency and platform gates, not a new Foundation ranking.

Formal uninstrumented completed capture totals400 trials and84,400,000
physical records; the24 diagnostic trials separately verify2,424,000 and are
not counted as time-performance qualification. No source edit, build or test
from this task overlaps the formal PMU/file/long captures.

## Resource change

Native x86_64 sizeof(Journal)704→768 bytes; SingleProducerControl320→384
bytes, alignment64 unchanged (`resources.zig`/before-after logs). Each already
allocated Journal grows64 process-local bytes, including shared/main queues;
no new allocations are introduced. P4 SPSC with its main+four channel journals
has320 extra bytes. Mapped journal/header/slot/schema formats and configured
queue/file/I/O backing budgets remain unchanged. This is object size, not
whole process RSS or transitive consumer stack.

## Composite gate

`zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all` passes
93/93 build steps and552/552 Zig tests, including the three new owning space
notification tests, public actual full-SPSC shutdown and worker error, independent
five-mode/single-threaded/source-distribution packages, wire/schema mutation
matrix, native Linux host qualification, and12 actual random-time process-crash
scenarios. Every complete ACK is covered by output or recovery; observed replay
overlap remains allowed at-least-once behavior. The TSC check falls back to
native when calibration is unstable, not new acceleration qualification.

Direct gate commands and the tested public benchmark build are:

```sh
zig test src/root.zig -O ReleaseSafe --test-filter 'queue progress' --test-filter 'coalesced' --test-filter 'quantum' --test-filter 'shared admission'
zig test -O ReleaseSafe --dep kron -Mroot=tests/runtime_integration.zig -Mkron=src/root.zig --test-filter 'SPSC'
zig build-exe -O ReleaseFast --dep kron -Mroot=bench/cpp_reference/kron_reference.zig -O ReleaseFast -Mkron=src/root.zig -femit-bin=bench/evidence/2026-11-01-queue-progress/kron-ref-after-final
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
zig build check-platforms -Doptimize=ReleaseSafe -j2 --summary all
```

Compile the two archived diagnostic harnesses with the appropriate frozen before/
after library sources. Their extra wait counters deliberately affect timing;
the ordinary public benchmark binary is used for every formal performance row.
Final composite/platform identities and complete measurement audits are recorded
in qualification.json. Nine ReleaseSafe platform object targets pass10/10
build steps (`platforms.log`). Foreign object compilation does
not replace device execution or establish new physical power-loss coverage.
