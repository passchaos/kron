# Memory/Mmap consumer service budget

`consumer_batches_per_queue` selects how many service quanta the background
processes consecutively from one queue, from 1 to 4, defaulting to 4. Each quantum
contains at most 64 records; the current implementation can merge already-ready
contiguous records within the remaining quanta into one checked delivery window,
then take a new window or serve the next queue after complete writing/barriers
and per-record reclamation. A short window also charges at least one quantum, so
the default serves at most 256 records consecutively, and an explicit 1 serves at
most 64. The shared main queue and SPSC channels use the same budget, and a single
queue still follows it. Synchronous mode has no background drain, but the option
range is still validated at initialization. See
[coalesced delivery](coalesced-delivery.md) for merge and acknowledgement
boundaries.

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .low_latency,
    .memory_queue = .{ .capacity = 256, .max_record_bytes = 512 },
    .max_thread_channels = 4,
    .thread_channel_capacity = 256,
    .consumer_batches_per_queue = 1,
    .routes = routes,
});
```

Mmap uses the same option with the queue configuration replaced by a journal file.
The budget is not a latency deadline and does not change accepted/written/
durable, per-thread FIFO, CRC, schema checks, configuration snapshots, or slot
reclamation. It is fixed at creation and does not pass through hot configuration
publication; 0 or values above 4 return `InvalidOptions` before allocation and
journal creation.

A smaller budget can shorten the service interval for a backlogged peer while
changing batch locality and the waiting distribution of producers on a full
queue. p99 and p99.9 may move in different directions, and a fairer service order
does not imply lower values at every quantile. The default 4 preserves existing
scheduling; applications should measure throughput, p99, and p99.9 separately for
their own Memory/Mmap workloads before choosing.

A deterministic real-background test installs a barrier at the first write
callback, then backs up 160 busy logs and one peer log. Across Memory/Mmap and
shared peer/SPSC peer combinations, budgets 1/2/3/4 serve the peer after the
1st/65th/129th/161st busy output respectively; per-thread sequence, written
counts, zero remaining backlog, and zero allocation after initialization are
verified. This verification bounds the service interval by record count and does
not claim an OS wall-clock scheduling bound.

Public integration tests also observe a real futex wait on a full SPSC queue;
shutdown wakes the admitted producer, which returns `rejected_closing` and aborts
its unfinished reservation. Memory/Mmap separately verify no accepted records, no
output, and no residual backlog. Existing deadline, configuration replacement,
file-error, and recovery tests continue to constrain the same lifecycle.

The former cross-library reference harness supported `--consumer-batches=1`
through 4 and stored the value in JSON reports; that harness has been removed.
Complete Memory/Mmap performance reports and measurement sources are no longer
tracked.

Forty complete-file trials from the same executable verified Memory/Mmap with four
producers, 100k measured records + 1k warmup, five sampled/batch pairs, and 4.04
million JSON records. Moving the budget from 4 to 1 changed Memory p99 median
from about 10.9 to 82.8 µs and p99.9 from about 377.7 to 114.7 µs; Mmap p99 from
about 9.1 to 84.5 µs and p99.9 from about 391.0 to 110.7 µs. All quantiles and
throughput groups were inconclusive because spread exceeded the threshold, and
the trade-off was also observed in earlier independent candidate comparisons. The
default remains 4; explicit 1 cannot be described as overall faster or as lower
tail latency everywhere.

A separate cross-queue 64-record round-coalescing window was tested on
`714c470/e8bd353`: each queue kept its original 1..4 quanta, the total window was
at most 256 records, output barriers were shared, and per-record CRC/reclaim was
retained. Four-queue Memory/Mmap × inline/schema, sparse six-queue capacity
splitting, peek/flush/durable and late-corruption targeted Debug/Safe/Fast tests
passed 26 each, and the original 1/65/129/161 peer positions were preserved.
However, 440 complete-workflow/PMU/single-quantum control trials verifying 52.44
million JSON records left throughput/tail latency inconclusive because of
variance; inline SPSC Memory/Mmap P4 p99.9 median moved from about 352 to 86 µs
while p99 moved from about 0.6 to 72–73 µs, and user instructions rose about
0.58%–0.71%. Another 80 trials against the existing single-quantum control did not
prove a general advantage, so the candidate was fully rejected and production
restored the original scheduling. Future waiting-path optimization should start
from actual progress/wakeup evidence rather than generalizing a lower p99.9 into a
default policy.

SPSC full-queue waiting now uses the local queue's in-process space epoch.
Completion on another queue does not advance this epoch; completion of this
queue's tombstone/acknowledged window advances it and wakes an existing waiter.
Only one legitimate SPSC owner registers a wait, and after registration it
rechecks worker errors/closing; the seq_cst epoch/registration order ensures a
concurrent notification either wakes the registered waiter or changes the
expected value observed by the futex check. Worker exit/errors and shutdown
notify every stable channel, even when its own queue made no write progress. The
original global progress protocol for shared producers/control is unchanged, as
are service budget and FIFO.

Twelve independent diagnostic trials before/after verified 2.424 million JSON
records; wait returns for unchanged local-queue written fell from 832–1137 to 0
per SPSC trial. This observation includes immediate returns and does not directly
mean real sleep count or complete speed. Formal 400 file/PMU/one-million-record
checks verified 84.40 million JSON records. Memory inline SPSC P4 long sampled
call p99.9 median moved from 366.312 to 340.708 µs (−6.99%), with both-side
CV/spread passing and non-overlapping intervals; p50/p99 and Mmap tails still did
not qualify generally, and the extreme wait remains about 340 µs. Short-workflow
P1 throughput retained a negative median around 10% and large variance; the
one-million-record P1 batch did not reproduce it (median +2.26%, intervals
overlapping). Queue/file budgets and allocation counts did not increase, and each
Journal gains 64 bytes of in-process control. Real concurrency regressions cover
local-queue reclamation, shutdown before sleep, epoch wrap, and worker failures on
different queues. This does not update a cross-library ranking.

A follow-up experiment that registered waiters for global progress was rejected:
SPSC global wake calls fell from about 414–425 to 4–8 and shared calls roughly
halved, but 200 complete workflows plus 80 longer shared independent rechecks
(44.28 million JSON records) did not prove an overall shared-path gain. Memory
batch rechecks had P1/P4 medians of −1.02%/−2.91% with overlapping intervals;
other throughput and tail groups were mixed. Production keeps the original
notification protocol. Ordinary applications should prefer shared Memory/Mmap;
SPSC remains an advanced option and degradation control.
