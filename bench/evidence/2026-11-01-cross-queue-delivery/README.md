# Cross-queue checked delivery windows

Baseline `714c470` has the production implementation measured as `e8bd353` in
the owning current Foundation comparison. The candidate serves multiple ready
queues in rounds, taking at most64 checked records from each queue, merging
up to256 into a delivery window. Every queue keeps its original1..4 service
quanta and at most256 records per worker pass. Short windows still cost one
quantum. A window never waits for a producer or passes a live reservation gap.

Single ready queue paths keep their existing coalesced64..256-record service.
All peers are still visited in the same pass, including peers that receive
records while a queue is being served. After service, only unvisited ready
peers with unspent budgets can enter a combined window. A single shared queue
has a direct path. Multi-queue groups preserve their traversal order and each
queue's FIFO. A partially filled tracking array flushes before adding another
64-record slice; tracking capacity never grows beyond256 records.

The single/multiple-origin checked render/confirmation logic is extracted to
`core/consumer_delivery.zig`; the runtime owns scheduling, lifecycle and sink
serialization. Every record resolves its own journal's schema and retains its
configuration View/record pin. All required output/durable barriers for the
combined window succeed before any record can be reclaimed. Reclaim still
performs the second CRC check and acknowledges the actual successful global
prefix, mapped back to each origin. Prior completed output can replay on failure,
consistent with the original at-least-once contract. No queue/file/I/O/heap
budget is increased; additional bounded consumer arrays and emitted stack
allocation must be accounted separately.

## Deterministic evidence

Four real SPSC queues each hold192 ready records while a blocking shared record
establishes the input boundary. The next window completes64 from every peer,
instead of draining192 from one peer first. Memory/Mmap×inline/schema variants
verify every channel sequence and written/pending, with a failing allocator
after preparation. The owning previous quantum tests still assert peer positions
1/65/129/161 for budgets1/2/3/4. A six-queue case with a one-record peer forces
the tracking window to split before a remaining suffix smaller than64 entries.

Window flush failure retains all128 participating records/pins. Late corruption
after output confirms64 records from the first queue and32 from the second;
the second queue's32 remaining records stay owned. Initial last-record CRC
damage in the second queue produces no combined-window output and retains
both64-record queues. A Mmap required-durable sync failure retains all128 slots
with written/durable targets zero for each peer. The already completed leading
shared record remains written. Existing single-window late damage and older
configuration pin/lease tests remain in the selected gate.

Final directed Debug/Safe/Fast scopes each pass26 tests. Initial errors are
retained: first refactor omitted origin selection for schema lookup; initial
ready-queue scan deferred late arrivals and failed old peer ordering; initial
tests reached the old single-queue path before the combined group. The final
schedule rechecks only unvisited peers and passes the original peer regression.
The first PMU launch preceded completed provenance and failed before any trial;
it is recorded separately and excluded. Final sources/binary freeze precedes
the real capture; no source edits or builds overlap measurement from this task.

## Measurements

The public fullJSON reference with system time, five numeric attributes,
256 slots/512-byte payloads,64KiB file buffer and default4 service quanta remains
unchanged. The owning independent output oracle checks every physical record,
ID/field/hash, final written/drop/pending and close. Init/preparation, producer,
flush/shutdown/cleanup and sampled call p50/p99/p99.9 remain separate. Actual
portable backend and fixed CPU0/2/4/6/8/10 affinity are checked.

`measure.py --pmu` takes40 complete300k-record user counter trials for SPSC
Memory/Mmap×inline/schema P4. `measure.py` runs320 full file trials across
Memory/Mmap×shared/SPSC×P1/P4×inline/schema×batch/sampled, five pairs. Queue
storage, reliability, schema and per-producer budgets are not silently exchanged.
No strict durable media flush is part of the performance workload. User PMU
includes setup and excludes kernel work. Larger service fairness may increase
p99 while lowering p99.9; no percentile is selected in isolation for promotion.
Every slower/incomplete result remains, and final decisions follow the measured
full distributions, not the source-level number of barriers.

## Complete initial comparison

The320-trial complete file capture independently verifies32,320,000 physical
JSON records;40 PMU trials add12,040,000. All records, budgets and file hashes
pass. The host is noisy: all throughput/percentile comparisons in this capture
remain inconclusive. Full distributions and bootstrap intervals are retained.

SPSC P4 inline Memory/Mmap p99.9 medians fall351712→86377ns and352718→86549ns,
while p99 increases589→72322ns and668→73213ns. Schema Memory/Mmap p99.9 falls
344101→92189ns and334951→93048ns; p99 rises884→72762ns and956→69936ns.
P50 also has higher medians. These are not universal low-latency improvements.
The throughput medians for inline SPSC Memory/Mmap P4 are−4.35%/−4.87%;
schema SPSC Mmap P4 −6.42%. All original slower observations remain.

Four PMU groups have repeatable instruction increases0.58%–0.71% with
non-overlapping intervals, cycles are noisy and no throughput benefit is
qualified. Native emitted stack allocations are recorded per function:
baseline drainJournal40712B; candidate drainJournal40392B, drainQueues21512B
and multiple-origin consumer_delivery21928B. A call-chain uses both scheduler
and delivery frames, so these cannot be read as lower total stack from the
smaller single function. Pushes/callees and total transitive stack are excluded.

`measure.py --one-quantum-control` makes a separate80-trial comparison between
the original already-public consumer-batches=1 and candidate default4 for
SPSC Memory/Mmap×inline/schema P4. Those are intentionally different service
budgets, explicitly stored in each row. The purpose is to check whether a new
mechanism improves on an existing tail-latency option, not to count that control
as the same-default baseline. Its complete results determine whether the extra
scheduling/ownership cost is justified.

## Decision: reject, keep the existing scheduler

All440 trials independently verify **52,440,000 physical JSON records**. The
80-trial control shows only inconclusive differences against the already-public
one-quantum option. Memory inline control p99/p99.9 medians90227/111254ns vs
candidate73668/96130ns; schema85308/107360ns vs70117/88857ns. Mmap inline
control64956/144559ns vs71983/152196ns, with a negative sampled-throughput
median for the candidate. All intervals/repeatability limits remain. This
control is explicitly consumer-batches1 vs candidate4; it is not merged into
the same-default comparison or used to change the default budget.

The cross-queue protocol passes the selected semantic gates but does not qualify
an overall throughput/tail improvement or a worthwhile advantage over existing
configuration. P50/p99 medians worsen sharply against the default scheduler,
instructions increase, and transitive consumer stack also grows. The candidate
is rejected in its entirety; production src is restored exactly to714c470,
whose owning current implementation is e8bd353 and has549-test/nine-platform
evidence. Full candidate implementation/tests remain in after-source.tar.gz.
No cross-queue scheduling mode is shipped, and no broad gate is rerun for this
rejected candidate. All slower and failed captures are retained. Future waiting
work should examine actual waiter wakeups/progress and lifecycle boundaries,
not assume smaller per-queue slices automatically improve every percentile.
