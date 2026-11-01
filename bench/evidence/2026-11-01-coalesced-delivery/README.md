# Coalesced ready records within bounded service quanta

Baseline Git commit `45f5ec1`. The consumer previously took up to four
64-record checked batches from a queue, flushing/reclaiming each separately.
The candidate takes a consecutive already-ready window up to its remaining
service budget (64..256 records), reusing protected configuration Views and
performing output barriers before per-record checked reclaim.

A short window still consumes ceil(records/64) quanta, so a queue cannot
serve more records because new producers arrive during the output call.
At default4, at most256 records are served before visiting peers; explicit1
still has a64-record bound. No waiting to fill a window or timer is added.
Existing internal reservation/tombstone and recovered/live boundaries end
a checked window. Configuration groups remain64, matching the bounded
configuration table even when a window contains256 records.

Every record retains its original schema/CRC/length checks, captured route
version, required written/durable barriers, second checked reclaim, record
pin and acknowledgement. Flush/sync failure retains every window record;
late reclaim damage acknowledges the actual successful prefix only.
Successful earlier output may be replayed on failure, consistent with the
existing at-least-once recovery contract.

## Source and semantic proof

`before-source.tar.gz` freezes the baseline. `after-source.tar.gz` and
`after-provenance.json` identify the completed portable capture, before later
fault-test additions. `final-source.tar.gz` and the final io_uring provenance
freeze the actual final tested source. The production algorithm is identical
between the completed captures; added test bodies are recorded separately.
`implementation.patch` and `final-implementation.patch` identify both stages.
Binary/source guards execute before and after every file trial.

The original deterministic backlog check fails with first_flush_records64
instead of255 (`before-test.log`). The candidate verifies255 queued records
in the first barrier for Memory/Mmap, shared/SPSC and inline/schema variants,
with a failing allocator after initialization. Boundary tests verify:

- initial late-window corruption produces zero output and retains all255;
- mixed old/new configurations on final flush or durable-sync failure retain
  all255 slots,150 old pins and105 new pins; batch readers unwind correctly;
- late corruption after all output acknowledges only190 records, written
  target191 (including an initial tombstone) and65 retained old-version pins;
- all service budgets1..4 retain queued peer positions1/65/129/161 and FIFO;
- empty/internal-gap behavior, shutdown/deadline and public file faults remain
  covered by the owning runtime/journal tests.

`coalesced-final-all-safe.log`, `coalesced-all-debug.log` and
`coalesced-all-fast.log` each pass15 tests including import fixtures and an
existing diagnostic test. The five new real-runtime tests plus the service
budget test are substantive checks. The intermediate `coalesced-all-safe.log`
records a failed test setup that requested durable reclamation on a memory
queue; the final fault setup uses Mmap for that variant and passes.

Fixed tracking arrays grow from5440 to21760 bytes on native x86_64,
+16320 stack bytes (resources.zig/log). This covers records/channels/snapshot
pointers/reclaim boundaries only, not the complete compiler frame. The64
protected configuration group array does not grow. No heap or producer
allocation, journal capacity or sink/I/O budget is added.

## Complete portable file workflow

160/160 trials independently verify **16,160,000 physical JSON records**:
Memory/Mmap, shared/SPSC, P1/P4, batch/sampled, five alternating pairs.
Each trial has100k measured and1k warmup, complete metadata/five attributes,
system wall clock,256 slots/512-byte payloads,64KiB file buffer and default4
service quanta. Affinity is CPU0/2/4/6/8/10 on the loaded Linux/i9-13900K/ext4
host. Every actual backend is portable and accepted=written, pending/drop0.
Throughput includes producer, backend formatting/file writes, final written
flush, shutdown and object/file cleanup; init/preparation remain separate.
No strict durable media flush is requested by these performance trials.

| Portable batch configuration | Before M/s | After M/s | Median change | Qualification |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 |2.095|2.188|+4.44%|repeatable; bootstrap intervals overlap|
| shared Memory P4 |2.106|2.251|+6.90%|repeatable; intervals do not overlap|
| SPSC Memory P1 |2.212|2.340|+5.78%|repeatable; intervals do not overlap|
| SPSC Memory P4 |2.144|2.358|+9.97%|repeatable; intervals do not overlap|
| shared Mmap P1 |2.118|2.149|+1.44%|repeatable; intervals overlap|
| shared Mmap P4 |2.068|2.092|+1.19%|inconclusive|
| SPSC Mmap P1 |2.036|2.114|+3.85%|inconclusive|
| SPSC Mmap P4 |1.710|2.228|+30.29%|inconclusive|

Repeatable here requires both sides' CV and relative spread below10%.
The Mmap positive medians are not stable improvements. All slow observations
and per-metric bootstrap intervals remain in comparison.json and all files'
counts/hashes in workflow-results.jsonl. The counter data does not infer
cross-library Foundation superiority or arbitrary business workload results.

Sampled shared Memory P4 p99 median increases16196->26613ns and p99.9
18814->29753ns (both inconclusive); shared Mmap P4 p99 increases15806->27403ns
and p99.9 increases17738->57587ns, also inconclusive. SPSC Memory P4 p99
median falls10374->510ns, while p99.9 is370434->346557ns, both inconclusive.
P50 or throughput improvements cannot be presented as universal tail wins.
Explicit one-quantum service remains available for a smaller64-record window.

## Independent io_uring workflow

The initial io_uring run stopped when added test sources changed a watched
hash. It preserves54 completed successful rows (5,454,000 verified records)
in uring-interrupted-results.jsonl, log and provenance. It is incomplete and
has no passing full-comparison qualification. After final source freeze,
an independent fresh80-trial capture completes **8,080,000 physical records**,
Memory/Mmap shared/SPSC P4, batch/sampled, five pairs. Each row confirms
actual linux_uring selection, unchanged budgets and complete-file verification.

| io_uring batch P4 | Before M/s | After M/s | Median change | Qualification |
| --- | ---: | ---: | ---: | --- |
| shared Memory |1.739|1.985|+14.18%|repeatable; intervals do not overlap|
| SPSC Memory |1.781|2.202|+23.62%|repeatable; intervals do not overlap|
| shared Mmap |1.746|1.964|+12.48%|inconclusive|
| SPSC Mmap |1.491|1.603|+7.52%|inconclusive|

All successful final portable/io_uring trials total240 and24,240,000 physical
records. The two captures occur in separate windows, so their after numbers
must not be treated as a same-round backend ranking. Shared Memory io_uring
p99 increases22459->34674ns (repeatable) and p99.9 increases26216->42011ns
(inconclusive), reflecting longer completion intervals. SPSC Memory io_uring
p99.9 falls448298->392267ns within the local repeatability budget. All full
percentile distributions and slow rows are retained in uring-comparison.json.

## Syscalls and durability

A traced100k shared Memory P4 portable pair independently verifies202000
physical records. Pwritev calls fall1581->833; total futex calls fall9184->4533.
Tracing changes the schedule, so these are diagnostic operation-count
observations, not the source of the qualified wall-time results. Original
traces/workflow and exact file-oracle reports remain in before/after files.

New static ReleaseSafe testwriter inside isolated QEMU validates schema
ACK31 after16-slot reuse and inline ACK3 after actual child-VM SIGKILL.
Every acknowledged JSON record and durable checkpoint survives. Snapshot
verification leaves the original crash-evidence image unchanged. Transcript,
writer/kernel/image hashes and raw-cache paths are recorded in vm-results.json;
this is specific Linux6.8/ext4 virtual-machine evidence, not physical host
power loss or all-filesystem qualification. The per-record durable reclaim
algorithm remains unchanged; deterministic larger-window durable failure
has its separate runtime check above.

## Reproduction and gates

```sh
zig test src/root.zig -O ReleaseSafe --test-filter 'coalesced'
zig test src/root.zig -O ReleaseSafe --test-filter 'quantum'
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
zig build check-platforms -Doptimize=ReleaseSafe -j2 --summary all
```

The final ReleaseSafe composite passes93/93 build steps and540/540 Zig
tests, including full decoder/fuzz matrices, runtime SIGKILL recovery,
independent five-mode/single-threaded/distribution packages and native host
qualification (`verify-safe.log`). Nine platform object targets pass10/10
build steps (`platforms.log`); this is cross-compilation evidence, not device
execution outside Linux. The final current source, frozen archives, capture
provenance, binary hashes and gate hashes are audited in qualification.json.

Rebuild the frozen before/after harnesses before replaying measure.py or
measure_uring.py into fresh destinations; preserve source/executable hashes
through capture. Final composite/platform gate results are bound to source
identities in qualification.json. All remaining stable
cross-library, tail, platform-device and fault qualification items stay in
docs/implementation-status.md.
