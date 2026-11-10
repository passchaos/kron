# Verification chronology (through 2026-11-09)

This page preserves the complete "recent verification" chronology from
`docs/implementation-status.md` on 2026-11-09 for tracing source revisions, gate
counts, positive/negative results, and evidence pointers. See
[acceptance status](../implementation-status.md) for current capabilities and
priorities. Measurement directories and cross-library harnesses have since been
removed; this English version keeps the conclusions without links.

## Verification records

After fixed-buffer schema encoding, the complete E-core matrix was rerun: 260
trials verified **26.26 million complete JSON records**. The durable 64 pairs gave
**24 kron leads, 4 peer leads, 36 inconclusive** (the previous final matrix was
24/19/21), and the 8 spool pairs gave **3/0/5**. The remaining four peer leads
were all mmap versus tracing: async-mmap-inline P1 batch **0.7860**, async-mmap-
schema P1 batch **0.8123**, SPSC-mmap-schema P1 batch **0.8119**, and SPSC-mmap-
schema P4 sampled **0.9035**. P1 Memory schema versus tracing turned into a lead
(async sampled 1.0778, SPSC sampled 1.0917), P1 mmap schema versus Foundation
sampled led at 1.1068/1.0986, and P4 async mmap schema versus tracing batch led at
1.0978; spool P4 batch was **7.952M** and sampled **7.468M**. Conclusion: durable
Memory had largely overtaken the comparison, and the remaining gap was
concentrated in P1 mmap batch versus tracing; some axes moved from peer lead to
inconclusive in this window.

The remaining optimization frontier was four peer leads, all mmap versus tracing.
The text fast path (producer render + consumer direct write, no CRC/recovery) at
P1 mmap was 2.03–2.30M, below the current binary schema's about 2.31M, showing
that converting the durable path into a text spool would not close the gap;
tracing's mmap advantage came from its text spool backend, not from output-file
mmap. Closing P1 mmap further required a contract-level change (durable text
spool/new fast path) or accepting the current boundary. Encoder dynamic-writer,
registry revalidation, render-cache threshold, consumer definition cache, and SPSC
token-validation micro-optimizations were each measured and rejected.

A render-cache index-lookup candidate was withdrawn: it mapped the cache directly
by shared journal/channel order and removed producer/consumer linear scans; in
five 500k A/B rounds, stable axes were SPSC P4 mmap 0.9973 and async mmap P1/P4
1.0044/1.0003, with no qualified lead. The profile hotspot did not translate into
measurable throughput: SPSC P4 consumer `drainJournal` self time was 29%, about
26% of samples were in batch-length loading after `peekChecked` returned (journal
handoff latency), and render-cache scanning was only about 10% of that.

Fixed-buffer boundary-check removal was also reviewed at instruction level:
reusing `codec.Output` unchecked writes gave median instructions 4367.06M versus
4359.14M (**+0.18%**, within noise), no gain, so production kept the checked
`wire.FixedOutput` version. This showed the remaining schema producer cost was
real work (measure/shape/CRC/journal), not a removable safety check.

A cross-journal prefetch candidate was withdrawn: it prefetched the next committed
slot for each SPSC channel before `drainAvailable` to overlap handoff latency with
first-channel processing; in five 500k A/B rounds, stable axes were SPSC mmap P4
**0.9868** and async Memory P4 **0.9894** (async Memory does not execute this
path, so at least part was binary-layout noise), with no qualified lead. A second
placement (prefetching the next journal after `peekBatchChecked` returned) made
the async Memory control regress stably to **0.9697 peer lead**, even though that
path does not execute prefetch, showing the `drainAvailable` restructuring/code
layout alone was enough to regress; both placements were withdrawn. Together with
the earlier per-record payload-prefetch rejection, the prefetch direction was
closed.

`reference_encoding.writeMeasured` previously used a dynamic `std.Io.Writer`
(`wire.StreamOutput`) for schema payloads: every header integer and every field
tag/value went through a vtable call and out-of-line `memcpy`; inline payloads
already used concrete `codec.Output`, and schema was the only remaining dynamic
writer hot path. `wire.FixedOutput` was added (fixed buffer + cursor, `int`
directly through `std.mem.writeInt`, `put` through checked `@memcpy`),
`codec.writeHeaderTo` became module-public, and `writeMeasured` switched fully to
FixedOutput. Payload bytes, error mapping (`BufferTooSmall`), and journal/CRC/
recovery contracts were unchanged. E-core five 500k A/B rounds: P1 async-Memory
**1.0766**, SPSC Memory **1.0607**, and SPSC mmap **1.0727** were qualified leads;
async-mmap median 1.0841 but one round was disturbed by same-host build tasks and
remained inconclusive; P4 four-axis medians were 0.9985–1.0312 with no qualified
negative. `perf stat` E-core instructions medians were async mmap P1 **−10.10%**,
async Memory P1 **−9.40%**, and async Memory P4 **−8.74%** (about −860 to −982
instructions/record). The complete root suite passed **484 tests, 1 skipped, 0
failed**; integration, async-storage, configurations, query, regression,
transactions, outputs, file-delivery, and single-threaded all passed; the
decoder-matrix build-runner failure reproduced on clean HEAD and direct runs
passed 3/3. Same-window five-round peer results: P1 Memory schema versus tracing
**1.0240 qualified lead**, P1 mmap schema versus Foundation **1.0256 qualified
lead**, P4 mmap schema versus tracing **1.1850 qualified lead**, while P1 mmap
schema versus tracing remained a 0.7957 peer lead (narrowed from 0.73–0.92); SPSC
supplemented P1 Memory versus tracing 1.0215 and P1 mmap versus Foundation 1.0408
qualified lead, with P1 mmap versus tracing 0.8128 peer lead. The only stable
durable peer lead was now **P1 mmap schema versus tracing** (async 0.796, SPSC
0.813), and tracing's mmap was about 25%–27% faster than its Memory, so the gap
came from the other side's mmap backend. The complete 260-trial matrix was not
rerun.

A consumer schema-definition cache candidate was withdrawn: caching the
`Definition` for the same schema ref inside `drainJournal` to avoid per-record
`resolveReadySchema`; in five 500k A/B rounds P1 Memory/mmap were 1.0006/1.0094
(inconclusive), but P4 mmap was **0.9425** (CI 0.9343–0.9602, stable peer lead)
and P4 Memory 0.9621 (noisy window). The local `Definition` copy and drain stack
layout cost exceeded the lookup saving, so production kept per-record
`resolveReadySchema`.

The render-cache schema threshold 1/4 was rejected: after fixed-buffer schema
encoding made the producer faster, the 1/4 threshold gave P1 Memory/mmap
0.8629/0.8747 (mmap stable peer lead) and P4 1.0250/1.0057; a single async
producer still could not absorb all rendering, and premature offload landed on
the producer critical path, so `capacity/2` was kept. In the same window, P1
schema cache-on/off was **1.1056/1.1171 qualified lead**, confirming adaptive
offload still brought about 10%–12%.

`Runtime` schema submission already validated ready/marker/id/version/hash through
`resolveReadySchema` in `submitSafeDestination`, but the reserve path called
`validateSchemaReady` again on the same reference, causing a duplicate registry
lookup per record. `Journal.reserveWithSchemaReady` and
`reserveSingleProducerWithSchemaReady` were added: when the same submission had
already resolved the reference, they only stamped the slot, with Debug builds
still rechecking; both shared async and SPSC switched. E-core 15 rounds × 500k
A/B (P1/P4 each 60.12 million complete JSON records): SPSC P1 Memory/mmap schema
batch was **1.0339/1.0398 qualified lead** (paired ratio spread 7.0%/3.1%, 95% CI
not crossing 1), async P1 Memory/mmap medians were 1.0058/1.0052 but window spread
exceeded the threshold, and P4 four-axis medians were 1.0046–1.0126 with no
qualified negative; `perf stat` E-core instructions medians were async P1
−0.49% and SPSC P1 −0.87% (about −48/−91 per record). Default durability/CRC/
recovery, journal format, and output bytes were unchanged. The complete `test`
passed except two local build-runner failures that reproduced on clean HEAD
(`kron-journal-fuzz`, `kron-compression`, both passing when run directly).

Six candidates were withdrawn and production stayed unchanged:
checkpoint-durable `MmapSpool` (dual-slot sidecar + `flush(.durable)` MS_SYNC +
recovery) passed correctness/recovery tests, but explicit durable ACK for a 30 MB
output took **85 ms–1.6 s** on this host; P4 written+ACK was about 0.9–1.0M,
below the journal durable path, and there was no per-record CRC, so it was
reverted. The experiment showed the durable ACK bottleneck was storage
synchronization rather than spool writing, and checkpoint mode had no value over
the journal. The others: a `text_format` validate-only path skipping the binary
size visitor was stable at 0.96–0.97 in nine P1 text A/B rounds and about parity at
P4, showing the current `codec.measure` inlining/layout was better; a
`text_format` trusted-capture-tree proof (internal opaque capability after
capture) was 0.94–0.97 at P1 text and about 1.025 at P4, with the P1 regression
exceeding the gain; shared-journal live pending using `tail - written` and
removing the live `occupied` RMW gave P1 Memory/mmap 0.975–0.981, P4 Memory/mmap
0.973–0.984, and P4 cache 0.975–0.976, with extra load/branch and layout cost
exceeding the RMW saving; `MmapSpool` 4 MiB `sync_threshold` (from 1 MiB) gave P1
batch +1.7%, P4 batch −1.9%, and P4 sampled −0.7%, mixed, so 1 MiB was kept; and
`MmapSpool` P4 `timestamp_period=256` versus ts64 gave batch 1.0014 and sampled
0.9873, so ts64 was kept.

`MmapSpool` added a `channel` option and completed multi-producer verification:
each thread creates an independent spool, file, and channel, avoiding a shared
tail/queue; the benchmark reference supported `--mode=spool --producers=4`, and
`run.py::verify` read region files in order and verified each record. E-core five-
round peer (60 runs, 6.06 million complete JSON records): P1 batch 3.24M, sampled
2.78M (1.39–1.47 qualified versus Foundation, 1.11 versus tracing sampled); **P4
batch 8.20M, sampled 7.62M, 2.57–2.72× Foundation and 2.91–3.22× tracing**. The
mode remained non-durable, with no journal/CRC/recovery and one file per
producer, so it could not replace a durable ranking, but it filled the durable
matrix's P4 mmap sampled peer lead versus Foundation. Channel/sequence tests were
added; complete `test` was **65/65 steps, 771/772 tests (one local skip)**;
`verify-local` was **159/159 steps, 805/806 tests (one local skip)**.

`render_cache` became backlog-adaptive: inline renders on the producer only when
`pending > capacity/4`, shared async schema at `pending > capacity/2`, and SPSC
schema at `pending > capacity*3/4`; otherwise the consumer stays deferred, adding
one monotonic `pending()` read before claim. E-core 32 configurations × 5 A/B
rounds (32.32 million complete JSON records): P1 inline all positive
**+8.5%–17.9%**, P1 schema **−2.3%–+3.9%** (all batch positive), P4 inline
**+38.9%–57.1%**, P4 schema **+7.9%–51.2%**; the ungated version's P1 regression
around 0.94 disappeared, and 32 pairs had no peer lead. Five-round peer
comparison (async+SPSC, 24.24 million complete JSON each): P1 Memory inline
sampled versus Foundation/tracing **1.219/1.029 qualified lead** (SPSC 1.273/
1.076), SPSC P4 Memory inline 1.20–1.32 all qualified, batch 1.228/0.995; P1
Memory schema batch versus Foundation 1.128 and sampled versus tracing 0.976
(small peer lead); P1 mmap durable improved from 0.706/0.811 to 0.765–0.840 but
remained a peer lead, and P1 mmap optimum remained `text_format` (0.917) or
`MmapSpool`. Backlog-threshold boundary tests were added; complete `test` was
**65/65 steps, 770/771 tests (one local skip)**; `verify-local` was **159/159
steps, 804/805 tests (one local skip)**. `render_cache` remained opt-in and
volatile, with journal/CRC/recovery/queue and output bytes unchanged; the
benchmark's `--kron-render-cache` now enabled adaptive cache for all producers.
`ThreadRegistry` added `attached_count`, and SPSC multi-producer schema switched
to the shared 1/2-ring threshold: 11 A/B rounds had P4 SPSC Memory schema batch
median +2.5% and P1 SPSC schema sampled parity, with the other seven P4 SPSC
schema axes at +0.1%–1.0% and no regressions. The complete E-core 240-trial matrix
(24.24 million JSON, all kron configurations with adaptive cache) then gave
**19 kron leads, 9 peer leads, 36 inconclusive**, a clear improvement over the
2026-11-04 quiet-window 11/13/40; remaining peer leads were all mmap (P1 mmap
versus tracing, P4 mmap sampled versus Foundation), while Memory paths had largely
overtaken. The final 260-trial matrix (durable 64 pairs + spool 8 pairs, 26.26
million JSON) gave durable **24/19/21** and spool **5/0/3**: peer mmap was faster
in this window (Foundation P4 mmap sampled 3.454M), durable peer leads exceeded
the quiet window, but Memory qualified leads also increased; spool P4 batch was
**8.565M**, sampled **7.568M**, and P1 3.265M/2.870M.

Two general rendering hot-path optimizations were retained: Runtime, fused wire
renderer, render cache, and `MmapSpool` switched to a `*const Event` render entry,
no longer copying about 200 bytes of event by value into the `renderWithTime`
stack frame; `decimal` writes `u64<100` directly as one or two bytes, skipping
digit-count estimation and the `/100` loop. E-core same-window seven-round A/B
(10 configurations, 14.14 million complete JSON records): `text_format` P1 Memory/
mmap **1.0908/1.1029**, `MmapSpool` batch/sampled **1.0653/1.0609**, durable P1
Memory/mmap **1.0482/1.0551**, render-cache P4 **1.0247**, durable P4 mmap
**1.0455**; only P4 text-Memory had a 0.9820 median with mixed direction and
spread above threshold, recorded as inconclusive. Five-round peer comparison (270
runs, 27.27 million complete JSON records): `text_format` P1 Memory and P4 Memory
were qualified leads over Foundation/tracing, `MmapSpool` P1 mmap sampled was
1.400/1.110 qualified over both, and `render_cache` P4 Memory had four groups at
1.30–1.38 qualified; `text_format` P1 mmap versus tracing remained a 0.917 peer
lead, and durable P1 mmap versus tracing/Foundation still lagged. Complete `test`
was **65/65 steps, 769/770 tests (one local skip)**; `verify-local` was **159/159
steps, 803/804 tests (one local skip)**. Public API, output bytes, and journal/
CRC/recovery/queue contracts were unchanged.

A real v1/v2 journal upgrade compatibility regression was added: v1 used
`format.initialize` + `checksum`, v2 used `format.initializeV2` + schema extension
+ `checksumV2`; under current V3 sources they created, committed, and peeked, and
after deinit/reopen with `recover=true` the payload was checked, asserting header
version and schema/CRC boundaries. Complete `test` was **65/65 steps, 744/745
tests (one local skip)**; `verify-local` was **159/159 steps, 778/779 tests (one
local skip)**.

A nested prepared + rolling + schema journal combined-recovery regression was
added: one route used `rolling_file` output, `.mmap` schema journal, and
`logging.prepared(shape)` with nested `field.group`/`field.array`; after three
records `flushDurable`/`shutdown`, the active rolling file was checked, then the
same journal was reopened, `flush()` asserted `journal_pending==0`, and a fourth
record was replayed. Complete `test` was **65/65 steps, 745/746 tests (one local
skip)**; `verify-local` was **159/159 steps, 779/780 tests (one local skip)**.

Pre-V3 old-binary v1/v2 journal fixtures were added: they were written by the
actual production source at commit `5b1fd7c`, with v1 having no schema and v2
containing schema plus two ordinary commit-unreleased records; the same old source
was also cross-compiled to aarch64-linux-musl and generated aarch64 v1/v2 fixtures
under QEMU user mode. Current V3 sources recovered payloads with `recover=true`
and checked old-binary scope/message through `resolveSchema`. Complete `test` was
**65/65 steps, 754/755 tests (one local skip)**; `verify-local` was **159/159
steps, 788/789 tests (one local skip)**.

The QEMU child-VM abrupt-termination gate was rerun with current HEAD: non-schema
single ACK1 and schema campaign 4/4 (ACK 17/31/8/3) all passed; a second boot
verified the valid highest-generation checkpoint, journal/output high-water marks,
and complete JSON through the ACK. Writer/kernel/busybox identity and each crash
image hash were recorded. This was a guest SIGKILL at a durable ACK boundary, not
host physical power loss; under `cache=writeback`, unflushed writes could still
reach the host backing file, so only the acknowledged sequence was asserted.

`FileSink`/`RollingFileSink` default backend changed from `.auto` to `.portable`:
with the same source, 20/20 complete workflows (runtime 12 configurations × 2
reps and managed 4 configurations × 2 reps) showed `linux_uring` written medians
about 13%–28% lower (managed about 15%–26%), and deferred-consumer flush
boundaries did not overlap SQE/CQE submission completion. `.auto`/`.linux_uring`
remained explicit options; the official cross-library benchmark already used
`.portable`, so the Foundation matrix and ranking were unchanged. Complete `test`
was **65/65 steps, 748/749 tests (one local skip)**; `verify-local` was **159/159
steps, 782/783 tests (one local skip)**.

A `quotedAscii` complete-ASCII direct-write candidate passed 22 escaping/boundary
tests; P-core five alternating pairs had instructions median about −0.40% and
cycles ratio 0.85–1.23, and 100k/500k complete-workflow matrices had no qualified
throughput or tail lead, so it was withdrawn by the threshold.

A shared async admission sharding candidate (v1 state+per-shard counters, v2
per-shard flags) passed the 65/65-step, 748/749-test correctness gate; v1 P4
cycles fell about 10%–20% but instructions rose slightly, and v2 cycle direction
was unstable. A 20-pair 500k-event A/B on idle E-core affinity
`[16,18,20,22,24,26]` gave v2 written ratio median **0.9672**, mean 0.9595, and
18/20 negatives, a stable regression; Runtime also grew from 12,800 to 13,376
bytes (+576 B), exceeding the object budget. The candidate was rejected and
production restored the baseline.

A queue-capacity diagnostic in the same E-core window: kron 512 versus 256
improved eight-configuration written medians by 1.2%–5.5%, but Foundation 512
improved Memory by 9.6%/8.9% and mmap sampled by 3.2%; at 256 versus 1024,
Foundation Memory improved 10.7% and mmap 8.3%, still larger than kron's 3.8%/
6.3%. The relative gap did not narrow, so default capacity stayed 256.

A FileSink buffer 64 KiB versus 128 KiB diagnostic in the same E-core window:
kron 128 KiB improved four runtime written medians by 0.4%–2.1%, while Foundation
was roughly flat or slightly negative; but managed P4 mmap batch four-way
interleave had kron128/Foundation64 = 0.5270, slightly below kron64/Foundation64 =
0.5325, so it did not translate into a relative lead. Default buffer stayed
64 KiB.

Sanitizer tooling diagnostic: Zig 0.16 `-fsanitize-thread` built successfully but
did not instrument this project's Zig code (no `__tsan` runtime; deliberate races
were not reported); Valgrind Helgrind detected ordinary races but falsely reported
about 1.63 million errors on Zig atomic loads/stores and aborted in async-storage
tests. Sanitizer coverage remained a toolchain limitation, and production was not
modified.

Consumer next-record payload `@prefetch` was withdrawn after E-core P4 20-pair A/B
written medians of 0.9848–0.9905 (3/4 configurations negative). A consumer
bounded-spin idle candidate (up to 256 epoch checks before `.sleep`) was withdrawn
after E-core P4 20-pair A/B written medians of 0.9748–0.9977 (4/4 negative),
consistent with existing `.spin` results and showing the P4 critical path was not
idle-wake latency. A consumer session JSON cache candidate (cache Runtime session
JSON bytes per batch and write directly when the record session matched) was
withdrawn after E-core P4 20-pair A/B written medians of 1.0025–1.0146 with mixed
mean and 0.3%–1.5% magnitude, below the qualified threshold.

The batch consumer acknowledgement candidate was retained: contiguous `.written`
records' journal reclaim and snapshot-pin release were merged into a batch
operation; `releaseBatchWritten` rechecked identity and slot CRC per record
(preserving late-damage successful-prefix semantics), then published the written
cursor, occupancy, and SPSC free position once, and `releaseChannelCount` used one
`fetchSub(count)` to release pins for the same `(snapshot, channel)`. `.durable`
records still used per-record `releaseAfter`. Three journal regressions were
added, and existing late-corruption Runtime prefix tests kept the 190/65 and 1/2
expectations. Complete `test` was **65/65 steps, 758/759 tests (one local skip)**;
`verify-local` was **159/159 steps, 792/793 tests (one local skip)**. E-core 16
configurations × 5 rounds × 2 binaries verified **16,160,000 JSON records**:
written had **12 leads, 0 negatives, 4 inconclusive**, with median ratios
1.0156–1.1074; all four inconclusive were P4 spread/interval misses, not stable
regressions. This did not update the Foundation cross-library ranking; the
candidate was still 1.8M–2.1M records/s versus Foundation's 2.4M–3.2M, and
default CRC/three checkpoints/queue budget/durable/recovery contracts were
unchanged.

After retaining batch acknowledgement, the complete E-core Foundation matrix was
rerun: 240 trials, verifying **24,240,000 complete JSON records**. Qualification
remained `target_not_met_in_selected_cases`; written comparison was **9 kron
leads, 20 peer leads, 35 inconclusive**. P1 batch/sampled versus Foundation
Memory all four groups were kron leads (async-Memory-inline 1.068/1.137, async-
Memory-schema 1.140/1.183, SPSC-Memory-inline 1.093/1.161, SPSC-Memory-schema
1.125/1.191); versus tracing most P1 groups were inconclusive, with only
SPSC-Memory-schema sampled 1.020 a lead. P4 still lagged: Foundation Memory batch
0.773–0.908 and mmap batch 0.554–0.658 peer leads; tracing P4 was mostly
inconclusive with some peer leads. The matrix was bound to its source and E-core
window and did not replace P-core; the overall ranking was not updated.

The render-offload diagnostic: current production binary at P4 async mmap inline
batch was **1.830M** records/s; replacing consumer rendering with a fixed 299-byte
payload raised the ceiling to **3.255M** (1.78×); with no rendering but each
producer additionally rendering and discarding, it reached **3.007M** (1.64×).
This showed consumer JSON rendering was the largest single P4 critical-path cost,
while four producers could still render with headroom. The earlier producer-
format failure came from writing complete JSON into the journal payload and
inflating CRC/memory traffic, not from the rendering work itself.

Earlier chronology (2026-11-01 through 2026-11-03) covered, in order: batch
acknowledgement and accounting; consumer scheduling budgets; schema consumer
fusion; ready-batch coalescing; admission View reuse; SPSC local-space
notification; prepared measurement reuse; static scalar capture and wire-size
accounting; decimal output direct-buffer writes; encoded validation reuse; wire
scalar rendering; JSON metadata/severity direct writes; CRC PCLMUL/slicing
variants; route-filter derived masks; decoder compatibility matrices; platform
host self-check; random runtime SIGKILL; package consumption and distribution;
TSC qualification; regex NFA active-state work; memory journal initialization and
fresh mmap header-only initialization; default clock callback and inline
candidates; shared written cursor and high-water updates; short-key comparisons;
typed capture; submit ABI; JSON member/predicate masks; CRC parallel collapse;
prefix CRC; and the earlier Foundation/spdlog/tracing same-round matrices. Each
was bound to its own source revision and window. The recurring conclusions were:
local instruction/cycle reductions did not automatically produce complete-
workflow throughput or tail gains; candidates with stable negative controls were
withdrawn; retained optimizations preserved default CRC, recovery, queue, and
completion contracts; and performance was highly CPU-topology sensitive, with
P-core/E-core and Memory/Mmap results reported separately rather than merged into
a universal ranking.
