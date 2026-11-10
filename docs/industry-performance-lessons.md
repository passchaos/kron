# Applying lessons from high-performance logging libraries

Design borrowing is based on actual hot paths and completion boundaries. The
repository no longer tracks cross-library harnesses or measured evidence, so the
notes below describe mechanisms and local observations rather than a current
cross-library ranking.

## Mechanisms confirmed in source

| Reference | Implementation or documentation inspected | Direction adopted and further work |
| --- | --- | --- |
| Quill 13.1 | `BackendWorker` builds `TransitEvent`s from frontend queues in batches and commits reads after a batch; one scan reuses clock samples | Keep typed capture and SPSC; reduce per-record configuration lookup, cursor, and statistics updates on the consumer. Journal slots cannot be released before required output completes |
| Foundation Logging | Memory uses contiguous `RecordBatch` byte ranges plus record end offsets; Mmap completes a batch after a successful write/flush; flush carries accepted targets | Adopt contiguous batches and whole-batch acknowledgement; the existing admission cut still defines flush scope. Preserve pending state, configuration pins, and real short-write handling |
| Foundation default formatter | Caches same-second date/timezone, computes output size first, resizes once, then copies and writes numbers; caches formatter clones per thread | Shared encoders should reduce repeated writer alignment and small copies. A static output descriptor must define invalidation and configuration generations; constant test bytes are not arbitrary events |
| fmtlog | Static metadata registered on first `logId`, type-specialized `getArgSizes`/`encodeArgs`, background `formatToFn`, reused fmt argument storage; single polling consumer, refresh by buffer size/oldest-byte delay/explicit `poll(true)` | Prepared schemas remain explicitly warmed. Batch policy must check both low-frequency visibility latency and terminal flush so later logs cannot indefinitely postpone the oldest pending record |
| NanoLog | Compile-time static information, runtime capture of dynamic values only, binary by default with offline decoding | Reuse static-information deduplication while keeping default text/JSON readable. Binary throughput must be reported separately and cannot rank complete readable JSON |
| Reckless | Deferred formatting, batched I/O, emphasis on application CPU/cache and queue saturation | Measure complete producer+worker+flush/shutdown workflows; expand business workloads and report CPU/memory/tail, not only median enqueue latency |
| BqLog | Official documentation emphasizes template caching, combined copy/hash, length backfill, batched I/O, and format/memory/CPU cost | Check whether capture and CRC can share one memory access without changing output protocol or node budgets; compressed output needs independent comparison |

Quill, Foundation, and fmtlog entries came from owned source; NanoLog/Reckless/
BqLog entries came from official README/design descriptions, which are not an
independent verification of every implementation or published performance.
fmtlog was read from the then-current master with file SHA-256 recorded because
commit lookup was unavailable; no fixed commit is claimed. No production
dependency was added and no upstream implementation was copied directly.

fmtlog's queue uses in-process log IDs, type-specialized functions, and partial
object representation; pointer arguments may require objects to live until poll
finishes. The cold/hot separation is useful, but its representation cannot be
written directly into kron's persistent journal. kron keeps explicit
borrowed-call lifetimes, string/bytes copies, and self-contained schema
identity, and times first registration/preparation separately. fmtlog also
publishes queue indices through volatile operations, which cannot be copied
directly into this library's cross-architecture release/acquire protocol.

## Workload differences found

A core PMU profile of a real one-million-record P4 SPSC-memory complete JSON file
workflow placed about 24% of samples in `slotChecksum`. kron computes CRC at
producer commit, consumer checked peek, and `releaseAfter` checked peek.
Foundation's normal Mmap peek reads only the slot descriptor, and
`complete_batch` checks ordering before publishing FREE; recovery scanning checks
CRC separately. The two designs therefore have different normal-operation
corruption-check costs. This explains part of the CPU-work difference but is not
the sole cause of the complete performance gap.

The first optimization kept the same IEEE CRC algorithm and changed it to
portable 16-byte slicing, preserving every checkpoint, schema-reference coverage,
initial value/reflection/final XOR, and recovery format. The read-only table grew
from 8 KiB to 16 KiB. Five fixed-CPU primitive PMU pairs reduced user cycles by
about 24.4% and increased instructions by about 4.3%; this is a cycle gain from
parallelizing the dependency chain, not fewer instructions. Microbenchmark time
and complete workflows still had noticeable host variance, and complete
throughput qualification stayed inconclusive.

On 2026-11-01, native x86_64 gained compile-time PCLMUL+SSE2 block folding,
while generic/non-x86/short inputs and tails kept the portable table.
Journal-shape CRC primitive medians for 256 B/512 B/2 KiB/16 KiB fell by about
80%/87%/90%/92%. Five complete-workflow PMU pairs reduced SPSC-memory P4 and
async-memory P1 user instructions by 15.33%/14.78%, and SPSC-memory P4 complete
throughput median rose from 1.393M to 1.816M records/s and met this round's noise
threshold. Vort 416-group interoperability, journal v1/v2 goldens, and the
complete ReleaseFast 503/503 tests passed. This is a native x86_64 path; a
same-round cross-library re-measurement would still be required for a ranking.
See [submission hotspots](performance-hotspots.md).

A 120-trial before/after complete-workflow comparison covered Memory/Mmap,
shared/SPSC, P1/P4, and sampled/batch, verifying 12.12 million logs. Another 10
one-million-record trials reviewed a short-batch P1 SPSC apparent regression and
verified 10.01 million logs; median throughput was about 1.23M → 1.31M, but the
candidate had a clear slow tail, so no stable improvement is claimed. All slow
values were retained.

## Implemented and follow-up work

Lock implementation alone does not explain the multi-producer complete-workflow
gap. In the Foundation source inspected, `parking_lot::Mutex/Condvar` protects
Memory/Mmap queue state; Memory exchanges contiguous `RecordBatch` values and
lets multiple batches share a file buffer, while Mmap acknowledges a whole batch
after the file flush. kron SPSC reserve does not take the shared queue mutex, but
still performs per-record CRC, configuration reference, and required-output
acknowledgement; slots are released only after each checked batch flushes. These
batch, acknowledgement, and wakeup policies all affect saturated-queue cost. No
same-implementation mutex-only comparison or isolated lock-wait measurement was
performed, so the performance gap cannot be attributed to `parking_lot`.

1. **Same-batch configuration and capability reuse**: consumer View reuse is
   implemented; a batch with the same generation/fingerprint looks up once, while
   cross-generation records keep independent Views and leases, and error paths
   release temporary readers while retaining record pins. Thirty-one same-batch
   shared/SPSC records confirmed a single lookup. A local shared-Memory P1
   measurement showed about 8.9% improvement; other combinations remained
   inconclusive. See [batch configuration reuse](batch-configuration.md). Later
   work precomputes the required durable-route bitmap per batch group to avoid
   rescanning per delivery/reclaim while preserving the original event's complete
   durable barrier mask.
2. **Intra-batch accounting and reclamation**: written accounting for contiguous
   channels is aggregated, reducing 31 actual shared/SPSC records from 31 atomic
   RMWs to one; error exits submit the truly acknowledged prefix, and concurrent
   sync/fallback updates still compose through `fetchAdd`. One hundred identical
   complete-file workflows all verified. Prepared SPSC-Mmap changed by about
   +3.5% and ordinary SPSC-Mmap by about −1.2%, with overlapping intervals; other
   combinations varied, so no stable speedup is claimed. See
   [batch acknowledgement and accounting](batch-accounting.md). Journal cursors,
   CRC, and `releaseAfter` remain per-record; further reclamation coalescing must
   first define the successful prefix when corruption occurs mid-batch, schema
   references, and the durable checkpoint contract.
3. **Encoding output path**: complete text/JSON/logfmt records reuse the same
   complete tree validation, while recursive output stays private and the public
   value API continues to validate independently. Original goldens and 12
   complete outputs/16,486 short-buffer prefixes matched the frozen source. Five
   encoding-probe pairs reduced user instructions by 14.27% and cycles by 17.90%;
   complete SPSC file workflows reduced instructions by 2.55%, but 100 ordinary
   file trials showed large candidate slow values, and another 10 long workflows
   did not qualify for stable throughput. See
   [encoder validation reuse](encoder-validation.md). Later work added
   width-free decimal output and direct complete-string consumption, producing
   native digits directly and chunking wide integers by 10^19 while preserving
   all JSON precision and generic Writer failure prefixes. Serial encoding
   probes reduced instructions by 18.50% and complete SPSC file workflows by
   6.22%, while complete throughput remained inconclusive. See
   [decimal and escaping output](decimal-output.md). A later round merged the
   default inline-admission tree validation with length accounting:
   `codec.measure` runs before the route predicate, and after acceptance
   `encodeSized` only checks level/capacity and writes the same event, avoiding a
   repeated length traversal; redaction and prepared schema keep independent
   entry points. Complete-workflow user instructions fell by about 2.5%, error
   ordering for filtered invalid levels and invalid trees is locked by tests, and
   throughput remained inconclusive. The consumer then reused the checked
   decoder's tree validation: `codec.decode`/`schema_codec.resolve` set an
   internal `Event.tree_validated` flag, internal `encodeDecoded` skips the second
   `ValueValidator` only for that proof, the public encoder ignores the hint and
   always validates, and runtime overwrites caller hints with trusted context.
   Five complete-workflow PMU pairs reduced SPSC-memory P4 and async-memory P1
   user instructions by 3.73%/4.49%; cycles and throughput remained
   inconclusive. A fused wire-to-JSON path for common shapes then reduced
   instructions by another 5.94%/6.20%. A checked wire typed visitor let the
   fused renderer skip intermediate `Value` materialization and generic tag
   dispatch while keeping the same complete tree checks; arrays/groups are still
   materialized before callbacks. Forty complete shared trials verified 12.04
   million JSON records and reduced instructions by 1.65%–1.69%, with complete
   throughput/tail still inconclusive. See
   [wire scalar evidence](performance-hotspots.md). The latest round writes JSON
   fixed metadata timestamp/session/sequence/route_mask/config_generation
   directly with comptime tags and raw `u64`/`i64`, skipping temporary `Value`,
   runtime tag switches, and the `u64`→`u128` path: four complete shared groups
   reduced instructions by another 2.45%–2.48%, and 80 uninstrumented workflows
   had positive throughput in all eight groups, six stable. See
   [metadata evidence](performance-hotspots.md). Next, study Foundation's
   `DefaultFormatter` pattern of computing `appended_size`, resizing once, and
   copying sequentially while preserving all value tags, UTF-8, source,
   boundaries, and zero output for invalid trees. Foundation's same-second date
   cache applies to calendar-time text; kron JSON currently carries full
   `timestamp_ns`, so reducing timestamp precision is not an acceptable trade.
4. **Capture and CRC combination**: investigate shared memory reads as described
   by BqLog, but record length, borrowed lifetime, and CRC coverage must complete
   within the same safe call, without exposing a reusable unchecked credential.

Implemented items are documented in their corresponding reports; the remaining
items are follow-up priorities. Each requires before-source, a same-semantics
complete workflow, fault gates, and explicit performance limits, followed by a
same-round comparison. Mobile-platform execution qualification and long-running
fuzz remain on the overall acceptance list.

Two configuration record-pin batch-release candidates were tested with 100
complete-file and 20 complete-PMU trials, verifying 32.24 million logs.
Semantics tests confirmed that 31 same-configuration records could combine 31
pin atomic decrements into one, but negative medians in several Memory groups,
high spread, and missing non-overlapping gains meant neither candidate qualified.
Production returned to per-record pin release, and the stronger late-corruption/
lease regression for old configurations was retained. Reference-count
optimization must account for per-record branches, state maintenance, cache
contention, and the complete workflow; visible duplicate operations only provide
a hypothesis.

## Memory/Mmap priorities after batch coalescing

Eight-digit chunking and cold buffered output were retained from consumer decimal
sampling: large native values generate u32 digit pairs from a 10^8 tail, small
values keep the original loop, and wide/streaming buffer frames move to a cold
path. The first two of three versions retained small/record negatives; the final
version reduced five instruction classes by about 9%–10%. One hundred forty
complete shared file trials verified 42.14 million JSON records, and Memory/Mmap
P1/P4 user instructions fell by 3.43%–3.47%; public integer/short-write behavior
and the complete Safe 151-step/639-test gate passed. Batch throughput medians
were positive but intervals overlapped, and a sampled Mmap P1 −6% did not
reproduce in an independent 20-trial recheck, so no general tail promise is made.
See [decimal chunking](decimal-output.md).

The current shared managed complete profile verifies 4.004 million JSON records;
P4 `begin`/`submitSafeDestination` remain the main producer self-time samples,
with concentrated samples at publication reads after filter/configuration reader
registration. A follow-up TLS scope-copy cache, uniform atomic mirror for
no-scope rules, and cold/hot split completed 120 PMU trials and 80 uninstrumented
workflows, verifying another 60.2 million JSON records. Reducing filter-reader
RMW did not produce an overall gain: TLS instructions rose about 0.76%–0.78%,
final shared throughput was mixed with all intervals overlapping, and tails had
no advantage; all candidates were withdrawn. Future work should continue from
consumer wire/number output instead of generalizing a mechanism from atomic
operation counts alone.

Ready records within the former four 64-record service quanta are now merged
into a window of up to 256. Two hundred forty complete-file trials verified
24.24 million physical JSON records; portable Memory four-group medians improved
4.4%–10.0%, with three groups having non-overlapping bootstrap medians; most
Mmap groups were unqualified. Independent io_uring P4 Memory groups improved
14.2%/23.6% by median, while shared Memory call p99 showed a repeatable negative.
A single trace pair (`pwritev` 1581→833, `futex` 9184→4533) proves only that this
diagnostic operation count fell. See [ready-batch coalescing](coalesced-delivery.md).

The table below lists candidates still to verify, ordered by current evidence,
common-path coverage, and implementation complexity; no percentage gain is
promised in advance. New rounds should first re-collect producer/consumer/syscall
profiles after batch coalescing instead of reusing old CRC shares to explain the
current bottleneck.

| Priority | Candidate and owning source | Current cost and proposed change | Verification focus |
| --- | --- | --- | --- |
| 1 | Bounded window and full-queue tail latency; `core/runtime.zig`, `core/delivery_batch.zig` | A fixed 256-record maximum trades throughput against slot-release frequency; study controlling the window by current backlog/output bytes while keeping the 64-record quantum budget and not adding fill waits | Sparse, burst, and sustained-saturation loads; complete written throughput, call p99/p99.9, low-frequency visibility, and peer service for P1/P4; do not select only the best quantile |
| 2 | Reduce consumer-to-file copies; `core/delivery.zig`, `sink/file.zig`, `backend/buffer_pool.zig` | Formatting currently writes to runtime scratch, FileSink copies into the file buffer, and io_uring copies again into a stable pool; study a private bounded reserve/commit or batched writer that submits records after complete validation | All format bytes and short-buffer failure prefixes; zero output for invalid records; in-flight buffer lifetime, partial writes, flush/shutdown, and rotation |
| 3 | Schema/prepared fused output and static metadata reuse; `core/runtime.zig`, `core/schema_codec.zig`, `encoder/wire_json.zig` | Fusion already covers inline v4 and schema windows with at least 64 ready records, requiring one route and no deferred messages/arguments; continue with template paths and static key/metadata escaping caches | Invalidate by schema identity and configuration generation; definitions persist before ready; preserve template semantics, nullable/nested/source/trace, error precedence, and recovery; time registration/preparation separately |
| 4 | Multi-producer atomics and cache-line contention; `core/runtime.zig`, `core/admission.zig`, `core/thread_registry.zig`, `journal/journal.zig` | Shared queue tail/accounting, global admission/wakeup, and channel counters still use atomics; SPSC also has global lifetime coordination; first diagnose with PMU/cache-to-cache data, then study hot-field separation or exact sharded statistics | P1/P4 scaling, system/user CPU, full-queue tails; flush admission cut, shutdown, error wakeups, and exact accounting must not change; current evidence cannot attribute this to `parking_lot` |
| 5 | Mmap cold start and channel preparation; `journal/storage.zig`, `platform/mapping/linux.zig`, `core/thread_registry.zig` | Mmap creation/initialization/file and directory publication still affect lifecycle; study explicit channel pre-creation, initialization memory access, and syscall coverage | Report init/preparation separately from written steady state; preserve disk/channel budgets, file/directory publication, and schema ordering; startup synchronization cost must not explain ordinary written steady-state gaps |
| 6 | io_uring cross-window pipelining; `backend/linux_uring.zig`, `core/runtime.zig` | The backend has a stable buffer pool and CQE progress, but runtime flushes after every delivery window, draining in-flight writes; study bounded pending windows so the next window formats while the previous window's I/O is in flight | Advance written/reclaim only after actual complete CQE success; mixed configuration pins, short writes, failure prefixes, shutdown/deadline, and resource bounds. Measure gains against portable in the same round; complexity is higher than earlier items |
| 7 | Explicit durable batched checkpoint/reclaim; `journal/journal.zig` | Durable `releaseAfter` currently performs data sync, checkpoint sync, and slot invalidation sync per record; study bounded whole-batch durable reclamation for a completed contiguous prefix | Checkpoint/slot-reuse ordering, torn writes, every failure boundary, and child-VM power-loss recovery; only meaningful for the durable path, since ordinary written experiments do not execute these per-record syncs |

An earlier conditional progress-wake candidate passed concurrency gates but did
not gain complete throughput and did not reduce saturated-load futex counts; the
original notification policy was restored. Together with the negative batch-pin
results, this indicates that follow-up work should measure new costs or change
the mechanism rather than repeat an unqualified candidate. PCLMUL CRC, default
redaction scratch removal, duplicate tree-validation removal, same-batch
configuration Views, written aggregation, and ready-batch coalescing are
implemented and are not open items.

A synchronous callback that rendered directly into FileSink staging was also
rejected: 280 complete trials verified 36.28 million JSON records, 40 PMU trials
increased user instructions by 0.48%–0.64%, all 240 complete throughput medians
overlapped, and several default Memory paths had negative medians. Correctness
gates passed, but the extra interface, callbacks, and state maintenance produced
no end-to-end gain; production returned to the verified source state. Future
copy reduction must use a different mechanism and re-measure cost; "one fewer
memcpy" is not automatically a speed claim.

Shared admission then reused an already validated View until `end` released the
reader, while accepted records kept independent pending pins and the original
CRC/barrier/reclaim. Real Memory/Mmap accounting, concurrent old leases, and
filtered/sampled/error regressions passed. Final 320 complete-file, 40 PMU, and
10 independent one-million-record trials verified 54.37 million JSON records;
shared schema Mmap P1 short workflows improved 9.55% by median and independent
long workflows 4.79%, with CV/spread and non-overlapping intervals. PMU shared
Memory P4 had a −3.36% negative median with non-overlapping intervals; most P4
workflow intervals overlapped, so no general P4 gain or complete CPU-instruction
reduction is claimed. Early overlapping long workflows were kept separately and
not counted in the formal 370-trial qualification.

A 64-record cross-queue round-coalescing window was tested and rejected: 440
complete trials/52.44 million JSON records showed lower p99.9 together with
significantly higher p99/p50, no overall throughput or single-quantum
qualification, and 0.58%–0.71% more user instructions; the scheduling/
cross-source acknowledgement cost and larger transitive stack were not adopted.
Production restored the same-round comparison logic. Future work should perform
bounded diagnostics on full-queue waiters and cross-queue wakeups for
`progress_epoch`, while preserving correct wakeups for worker errors, shutdown,
and reservation gaps.

SPSC full-queue waiting then gained a local-queue space notification while
keeping the original scheduling and global control waits. Twelve diagnostic
trials before/after showed that futex returns for unchanged local-queue written
dropped to zero, but that count alone is not a wall-time qualification. Formal
400 complete-file/PMU/one-million-record trials verified 84.40 million logs;
Memory inline SPSC P4 long sampled p99.9 median fell 6.99% with local
repeatability and non-overlapping intervals; p50/p99, Mmap, and ordinary
throughput mostly remained inconclusive. CRC/pin/barrier were not skipped and
reclaim was not advanced early; worker errors/shutdown notify all queues; the
registration/epoch SC handshake locks the pre-wait event boundary and adds 64
bytes of in-process control per journal. The remaining extreme wait of about
340 µs and qualification on other workloads still need work.

Reference links: [Quill BackendWorker](https://github.com/odygrd/quill/blob/v13.1.0/include/quill/backend/BackendWorker.h),
[fmtlog](https://github.com/MengRao/fmtlog),
[NanoLog](https://github.com/PlatformLab/NanoLog),
[Reckless](https://github.com/mattiasflodin/reckless),
[BqLog](https://github.com/Tencent/BqLog).
