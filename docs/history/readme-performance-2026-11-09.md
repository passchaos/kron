# README performance narrative snapshot (2026-11-09)

This snapshot preserves the detailed performance chronology from the 2026-11-09
README for tracing the source revisions, numbers, and evidence pointers of that
time. It is not the current interface or ranking; see
[acceptance status](../implementation-status.md) for current capabilities and the
[usage guide](../usage.md) for the current interface. Measurement directories and
cross-library harnesses have since been removed from the repository.

## Performance progress

A dual-topology complete-workflow profile verified 8.008 million JSON records to
locate current hotspots; it did not provide a new speed ranking.

A batch consumer acknowledgement candidate was retained in production: journal
reclaim and snapshot-pin release for contiguous `.written` records were merged
into a batch operation while retaining per-record identity/slot CRC rechecks and
late-damage successful-prefix semantics. E-core 16 configurations × 5 rounds × 2
binaries verified 16.16 million JSON records, with written results of 12 leads,
0 negatives, and 4 inconclusive (medians 1.0156–1.1074). Complete `test` passed
758/759 and `verify-local` 792/793; the cross-library ranking was not updated and
remained below Foundation.

After retaining that candidate, the E-core complete Foundation matrix (240 trials,
24.24 million JSON records) remained `target_not_met_in_selected_cases`: written
results were 9 kron leads, 20 peer leads, and 35 inconclusive. All eight
batch/sampled axes against Foundation Memory at P1 led (1.068–1.191); P4 Memory/
Mmap remained behind (0.554–0.908); against tracing, only SPSC-Memory-schema P1
sampled led at 1.020. P-core needed a separate rerun and the overall target
remained incomplete.

A render-offload diagnostic showed consumer JSON rendering was the largest single
P4 bottleneck: production reached 1.830M, removing consumer rendering reached
3.255M, and producer-side extra rendering still reached 3.007M. The next candidate
kept the binary journal/CRC/recovery and placed rendered output in an independent
side buffer/queue so the consumer only wrote it out, rather than writing JSON into
the journal payload.

Producer-rendered JSON cache was implemented as opt-in `render_cache`: the
producer renders into a volatile cache mapped directly by sequence, the consumer
writes hits directly, and misses/recovery fall back to deferred rendering. It is
off by default and supports per-journal cache for shared async and SPSC, single-
route JSON inline/schema. In a quiet window, P4 Memory batch/sampled reached
1.63/1.58 qualified leads (2.9M vs 1.8M); mmap medians were 1.51–1.61 but
inconclusive because of spread; four schema groups were 1.40–1.51; SPSC P4 eight
groups were 1.63–1.69 (5/8 leads). P1 regressed, so the benchmark initially
enabled it only for P4; later backlog-adaptive gating turned P1 inline into
+8%–20%. Complete `test` passed 766/767 and `verify-local` 800/801 (one local
skip). The latest E-core matrix was 12 kron leads, 8 peer leads, and 44
inconclusive; P4 cache axes led Foundation/tracing by 1.06–1.56, with the
remaining gap concentrated in P1 mmap/SPSC versus tracing. A quiet-window rerun
gave 11 leads/13 peer/40 inconclusive; P4 medians were async-Memory 2.97M,
SPSC-Memory 3.41M, and SPSC-Mmap 3.44–3.52M; SPSC P4 remained inconclusive because
of run spread although targeted A/B had qualified. The P-core cache matrix reran
at host load about 126 and all written results were inconclusive; targeted P-core
P4 A/B medians were 0.956–1.447, all inconclusive but with no qualified negative,
and needed a quiet-window rerun. A P1 consumer profile showed cache-off consumer
render plus two CRCs used about 35% of cycles, while cache-on made the producer
the bottleneck; the P1 gap versus tracing came from the durable producer path,
suggesting a separate opt-in volatile text-queue fast mode.

A volatile text fast path was implemented as opt-in `text_format` (requiring
`verify_crc=false`): the producer renders final JSON into the queue and the
consumer writes it directly; it supports Memory and `recover=false` mmap,
async/SPSC, and no journal recovery, while the default durable path is unchanged.
Fixed clock/session parity tests passed (async/SPSC, inline/schema). E-core
five-round A/B: P4 async Memory 3.84–3.96M (1.61–1.78), P4 SPSC Memory 4.80–5.06M
(2.06–2.32), P4 async mmap 3.50–4.04M (1.09–1.40); P1 async Memory 1.89–2.23M
(0.95–1.05 vs tracing), P1 SPSC 1.83–2.10M (0.89–0.97), P1 async mmap 2.03–2.30M
(0.72–0.87). P4 clearly led; P1 tracing mmap/SPSC remained the gap.

A P1 text-mmap profile showed the producer used about 43% of cycles (render about
20%, submit 10.5%, reserve 4.9%, begin 4.5%, measure 4.4%) and the consumer about
18.5%; closing the remaining tracing-mmap gap required a dedicated fast logger or
mmap output backend, not a single lightweight ring. A text-fast-path
measure-skipping candidate was inconclusive in all eight groups over five rounds
(medians 1.00–1.06) and was withdrawn. An independent FastRuntime candidate
reached P1 2.119M sleeping/2.281M spinning, did not exceed the text fast path or
close the tracing-mmap gap, and was withdrawn; the next step was an mmap
spool+writer backend. A specialized-render diagnostic showed a fixed-shape
template raised P1 text-mmap from 2.30M to 2.55M (P1 schema 2.23→2.41M, P1 sampled
inline 1.99→2.43M) and P4 about 1.02–1.06; all were inconclusive, but P1 medians
improved 10%–23% with no negatives. Generic rendering was a significant part of
the P1 gap; the next candidate was a general prepared fast renderer. A general
prepared-plan candidate regressed the schema axis because of per-record matches/
segmented metadata (P1 0.906, P4 0.831) and was withdrawn; a shape-enforcing format
logger also had no stable lead (P1 0.966, P4 batch 1.228, P4 sampled 0.975, all
inconclusive). The prepared-render direction was largely exhausted, and the next
step moved to an mmap spool+writer backend.

The P-core text matrix (240 trials, 24.24 million JSON records) had all 64/64
written comparisons inconclusive; P4 medians were async-Memory 3.03M, async-mmap
2.78–3.08M, SPSC-Memory 3.75–4.14M, and SPSC-mmap 3.83–4.25M, about 1.2–1.9×
Foundation/tracing, but window spread did not qualify. The matrix fixed
SPSC+mmap+text thread-channel text-flag propagation and added a parity regression.

Empty-context capture `tree_validated` reuse entered production: with no context
and no format_args, `appendFields`/`appendSlice` already prove the complete field
tree, so the renderer no longer repeats `validateEvent`. In spool E-core ts64 A/B,
producer render was about 7%–8% faster: spool batch 2.92–3.01M, sampled 2.57–2.62M;
versus tracing batch 1.072–1.086 and sampled 1.047–1.071; versus Foundation
1.32–1.45; r3 obtained 3/4 qualified leads and no qualified peer lead. The
production text fast path also benefited: P1 async-Memory batch 2.307M versus
Foundation/tracing 1.789/2.203M (1.286/1.038 qualified); P1 async-mmap batch
2.454M versus tracing 2.748M remained a 0.888 peer lead, the largest production
fast-path gap (2.525M/0.917 after 2026-11-08 render optimization). Paths with
context/format_args continued to be verified; default durable/CRC/three-checkpoint/
recovery contracts were unchanged. Complete `test` passed 766/767 and
`verify-local` 800/801 (one local skip).

`MmapSpool` single-producer opt-in fast mode entered production: the producer
renders directly into a file-backed mapping, a writer thread performs
`msync(MS_ASYNC)` at roughly 1 MiB intervals, and `shutdown` truncates to the last
complete record; there is no journal/CRC/recovery/ring/consumer. Three new tests
covered durable deferred-render byte parity, capacity/partial records, and
timestamp period; complete `test` passed 769/770 and `verify-local` 803/804 (one
local skip). P-core batch was 3.74–3.85M and sampled 3.19–3.35M; E-core batch
2.92–3.01M and sampled 2.57–2.62M; medians were 1.05–1.83× Foundation/tracing,
with no qualified peer lead, and some same-window pairs remained inconclusive
because of peer spread. The fast mode is opt-in, non-durable, single-producer, uses
about a 55 MiB mapping, and supports optional coarse timestamps; default durable/
CRC/three-checkpoint/recovery/queue contracts are unchanged.

`MmapSpool` added a `channel` option and verified multi-producer mode: each thread
creates an independent spool/file/channel, avoiding a shared tail/queue; the
benchmark reference supported `--mode=spool --producers=4` and verified region
files record by record. E-core five-round peer results: P1 batch 3.24M, sampled
2.78M (1.39–1.47 qualified vs Foundation, 1.11 vs tracing sampled); **P4 batch
8.20M, sampled 7.62M, 2.57–2.72× Foundation and 2.91–3.22× tracing**; the final
matrix window was P1 3.265M/2.870M and P4 8.565M/7.568M, filling the durable
matrix's P4 mmap sampled peer lead versus Foundation. The spool remains
non-durable, has no journal/CRC/recovery, and uses one file per producer; it
cannot replace a durable ranking. Complete `test` passed 771/772 and
`verify-local` 805/806 (one local skip).

The rendering hot path stopped copying `Event` by value and added direct small-
integer decimal writes: Runtime, fused wire renderer, render cache, and
`MmapSpool` switched to a `*const Event` entry, avoiding about 200 bytes of event
copy per render call chain; `decimal` writes `u64<100` directly as one or two
bytes. E-core same-window seven-round A/B (10 configurations): `text_format` P1
Memory **1.0908**, P1 mmap **1.1029**, `MmapSpool` batch/sampled **1.0653/1.0609**,
durable P1 Memory/mmap **1.0482/1.0551**, render-cache P4 **1.0247**, durable P4
mmap **1.0455**; only P4 text-Memory had a 0.9820 median with mixed direction and
spread above threshold, recorded as inconclusive. In five-round peer comparison,
`text_format` P1 Memory and P4 Memory were qualified leads over Foundation/tracing,
`MmapSpool` P1 mmap sampled was a qualified lead over both (1.40/1.11), and
`render_cache` P4 Memory had four qualified leads; remaining peer leads were P1
mmap text versus tracing at 0.917 and durable P1 mmap versus tracing/Foundation.
Complete `test` passed 769/770 and `verify-local` 803/804 (one local skip); default
durable/CRC/three-checkpoint/recovery/queue and journal format were unchanged.

`render_cache` became backlog-adaptive: inline renders on the producer only when
`pending > capacity/4`, shared async schema at `pending > capacity/2`, and SPSC
schema at `pending > capacity*3/4`; otherwise the consumer stays deferred, adding
only one monotonic `pending()` read before claim. E-core 32 configurations × 5
rounds A/B (32.32 million complete JSON records): P1 inline all positive
**+8.5%–17.9%**, P1 schema **−2.3%–+3.9%** (all batch positive), P4 inline
**+38.9%–57.1%**, P4 schema **+7.9%–51.2%**; the ungated version's P1 regression
around 0.94 disappeared, and 32 pairs had no peer lead. Five-round peer runs
(async+SPSC, 24.24 million JSON each): P1 Memory inline sampled versus Foundation/
tracing **1.219/1.029 qualified lead** (SPSC 1.273/1.076), batch 1.228/0.995; SPSC
P4 Memory inline 1.20–1.32 all qualified; P1 Memory schema batch versus Foundation
1.128 and sampled versus tracing 0.976 (small peer lead); P1 mmap durable versus
tracing improved from 0.706/0.811 to 0.765–0.906 but remained a peer lead, and P1
mmap optimum remained `text_format` (0.917) or `MmapSpool`. A later complete
E-core 240-trial matrix (24.24 million JSON, all kron configurations with adaptive
cache) gave **19 kron leads, 9 peer leads, 36 inconclusive**, a clear improvement
over the 2026-11-04 quiet-window 11/13/40; remaining peer leads were all in mmap
(P1 mmap versus tracing, P4 mmap sampled versus Foundation), while Memory paths
had largely overtaken. The final 260-trial matrix (durable 64 pairs + spool 8
pairs, 26.26 million JSON) gave durable 24/19/21 and spool 5/0/3: peer mmap was
faster in this window (Foundation P4 mmap sampled 3.454M), durable peer leads
exceeded the quiet window, but Memory qualified leads also increased; spool P4
batch was **8.565M**, sampled **7.568M**, and P1 3.265M/2.870M. Complete `test`
passed 770/771 and `verify-local` 804/805 (one local skip); `render_cache` remained
opt-in and volatile, with journal/CRC/recovery/queue and output bytes unchanged.

Mode selection: durable default (recovery/CRC/multiple routes/rolling); enable
`render_cache` when async JSON needs durability (adaptive; P1 Memory reached
tracing parity and P4 led; journal/CRC/recovery retained); `text_format` for P1
Memory/P4 maximum throughput without recovery; `MmapSpool` for the fastest P1 mmap,
single-producer, no recovery. Production `text_format` P1 mmap versus tracing was
still 0.917, and P1 mmap durable+cache was 0.79–0.83; see
[performance mode selection](../usage.md#performance-mode-selection).

Recent candidates for key scratch, short CRC, exact fixed-segment CRC, CAS pause,
flat CRC consumer validation, 16-row consumer validation CRC, THP mmap, consumer
spin, producer format, mutex reserve, and async file sink were withdrawn because
of control or tail regressions; V3 schema CRC was retained. The consumer-validation
version passed the real producer/generic CRC/24-row single-copy/object-budget
gates and had 50 qualified leads in 320 E-core trials, but async Mmap P1 sampled
schema p99 moved from 717 to 747 ns and a targeted recheck from 719 to 782 ns, so
it was rejected by the predetermined negative threshold. The 16-row version reused
only the original 16 rows with 0 B rodata growth, had 60 qualified leads and 23/32
written leads, but six latency/init negatives in the full run; six targeted
rechecks were all inconclusive in a window disturbed by an unrelated 100% CPU
test, so it was rejected by the threshold. V3 schema CRC folded reference+padding
into payload in one pass: two E-core windows had 81 qualified leads/0 negatives,
and the V1 control had only two 0.14%-level non-reproducible negatives in the first
window; same-format V3-control A/B had 27 leads/0 negatives, with the V1 path
showing only layout noise. V3 schema journal format was retained in production and
passed `verify-local` 157/157 steps, 775/776 tests, package-distribution 2/2, and
check-platforms 10/10; production hot path and measurement binary had identical
normalized instructions. After retention, the dual-topology complete Foundation
matrix (240 trials each, 24.24 million JSON) was E-core
`target_not_met_in_selected_cases` (29 lead/94 peer/293 inconclusive) and P-core
`inconclusive` (2 lead/414 inconclusive); kron leads concentrated in P1 Memory
batch, while P4/mmap and tracing still led. P4 mmap single-trial PMU showed kron
786M instructions/485M cycles versus Foundation 1.828B/904M: kron used less CPU
but was slower in wall-clock time; extended PMU also showed fewer cache misses/
context switches, and the critical path was single-threaded consumer decode+
format+write and file write throughput (kron about 543 MB/s versus Foundation about
745 MB/s). Consumer spin had 160 trials/0 leads/6 negatives and was rejected; the
P4 gap was not sleep/wake. A producer-format candidate (producer formats, consumer
only writes) was rejected on E-core async 160 inline trials with 0 leads/10
negatives (0.96–0.99): kron's producer already carries capture/encode/CRC/commit,
and moving formatting there made it the bottleneck. A mutex-reserve candidate
(reusing `sync_mutex`, no new Journal field) had 160 trials/0 leads, 5 P1
negatives, and 11 P4 negatives; `std.Io.Mutex` cost exceeded lock-free CAS. The
current-source `verify_crc=false` opt-in no-CRC diagnostic (E-core Memory 80
trials) had only 1 lead/10 negatives and did not reproduce the old compile-time
+20%–31%; however, a copied-source compile-time slot-CRC deletion diagnostic had
23 leads/0 negatives, with P1/P4 inline about 14%–17% faster and schema about 8%.
CRC remained a significant functional cost, and the runtime opt-in negatives more
likely came from branches/code layout; default CRC was retained, and cross-library
comparison needed to normalize Foundation's no-CRC cost. A FileSink writer-thread
double-buffer had 160 P1 trials/2 leads/3 negatives and P4 0 leads/11 negatives
and was rejected; six E-core CPUs were saturated by four producers + consumer +
writer, and barrier cost exceeded I/O overlap gains. `test-wire-scratch` and
`test-crc-segments` were retained for reuse, nested budgets, arbitrary seeds,
independent segments, and guard-page boundaries.

A waiter-count notification candidate completed 320 dual-core workflow trials and
32.32 million JSON records but had stable throughput and tail regressions and was
rejected. The latest flat CRC direct-index version removed old-table duplication;
640 dual-core trials verified 64.64 million JSON records, with E/P having 27/6
written groups locally ahead, but stable p99/p50 counterexamples remained and it
was rejected by the threshold. Production kept the original algorithm and default
protocols and had not fully overtaken the two Foundation frontends.

Reliability evidence was extended: ext4/XFS/Btrfs/F2FS 16-run child-VM abrupt-loss,
9p shared-filesystem behavior, real ENOSPC/read-only-FS/Journal preallocation
rejection, 1000-seed journal/archive fuzz, concurrent delivery/shutdown/mmap/
configuration replacement, and 1000/200-run soak; sanitizers remained limited by
the Zig TSan/Helgrind toolchain.

## Performance and release scope

The capability targeted Linux single-machine projects pinned to Zig 0.16, starting
with bounded Memory/portable and handling overload/shutdown errors in the
application. Windows, macOS, Android, and iOS had implementations and cross-
compilation/partial-link evidence but still needed real-device execution; the
package version was 0.1.0.

Complete workflow comparison included field capture, system clock, encoding,
actual output, written flush, shutdown, and cleanup. The latest complete same-round
cross-library comparison used the fd4e941 Logging baseline and Foundation's real
spdlog/Rust tracing frontends in 200 trials and 20.2 million output records: JSON
median throughput mostly led the spdlog combination, was mixed against tracing's
public JSON combination, and native `build_tracing` text was reported separately.
All cross-library speed ratios remained limited by variance, and SPSC p99.9 still
lagged. A 2026-11-02 reduced same-round spot check against Foundation + spdlog on
P-core found Memory P1 batch 1.125× meeting the local threshold, with other groups
inconclusive; against Foundation + Rust tracing, two identical 80-trial spot
checks disagreed, the first round's three local qualifications did not reproduce,
and the P-core comparison remained inconclusive. The physical-core (E-core)
window without SMT siblings was the opposite: tracing medians were higher in all
eight groups, five met the threshold, and spdlog led in five groups, with Mmap P4
batch about 0.580×. A subsequent E-core 160-trial complete JSON matrix (16.16
million records) had tracing ahead of kron async/SPSC in all 16 JSON comparisons;
spdlog led most P4/Mmap groups; kron async was near parity only in Memory P1 batch
(1.002×), SPSC Memory P1 sampled led slightly (1.063×), and other groups lagged;
SPSC improved about 5%–15% over async but not enough to change Foundation's lead.
The same-source P-core 160-trial matrix (16.16 million records) was affected by
host load, most groups exceeded 10% spread, and paired comparisons were
inconclusive; directionally kron async/SPSC was mostly ≥1 versus spdlog, behind
tracing in Memory P1/Mmap P1, and ahead in some P4 groups. A no-CRC diagnostic
(copied source, non-production) showed E-core Memory P1/P4 throughput +26.3%/
+31.1%, quantifying CRC producer/consumer validation as a major component of the
E-core gap. The explicit opt-in `MemoryQueueOptions.verify_crc=false` then applied
only to volatile Memory queues, defaulted to true, and was rejected for
mmap/recoverable journals; production build E-core P1/P4 improved 20.0%/23.1%.
This mode was only for applications explicitly accepting undetected memory
corruption risk. Performance was therefore highly CPU-topology sensitive, and no
single window was a universal ranking; dual-topology profiles and
feature-normalized comparison were required. Fresh mmap initialization reduced a
16.8 MB journal init median from 54.2/53.8 ms to 8.2/6.9 ms.

The decimal output optimization verified 140 real-file trials and 42.14 million
JSON records; shared Memory/Mmap P1/P4 complete user instructions fell steadily by
3.43%–3.47%; complete throughput/tail did not qualify generally, and the
cross-library ranking was not updated.

The checked wire typed visitor then passed validated scalars directly to a
tag-compiled writer, skipping intermediate `Value` materialization and generic
second dispatch; 40 complete shared real-file trials verified 12.04 million JSON
records, and Memory/Mmap P1/P4 user instructions fell 1.65%–1.69% by median, while
complete throughput/tail still did not qualify generally.

The latest round wrote JSON fixed metadata timestamp/session/sequence/route_mask/
config_generation directly with comptime tags and raw u64/i64, skipping temporary
`Value` unions, runtime tag dispatch, and the u64→u128 wide-integer path. Forty
complete shared trials verified 12.04 million JSON records, and four user
instruction groups fell 2.45%–2.48% by median; 80 uninstrumented workflows verified
24.08 million JSON records, all eight written throughput groups were positive, six
met the noise threshold, and P4 batch median intervals did not overlap; text/logfmt
controls and tail variance were retained.

The JSON severity field changed to one complete literal per Level enum, with `err`
still spelled `"err"`. JSON encoder probe instructions fell 2.05% by median; 40
complete shared trials verified 12.04 million JSON records, and four instruction
groups fell 1.68%–1.70% by median. Eighty workflow trials had mixed throughput, so
no general throughput promise was made.

Same-workload A/B between fd4e941 and the then-current source: E-core five-run
batch showed current Memory P1/P4 and Mmap P1/P4 faster by **14.6%/11.8%/11.4%/
7.2%**; P-core windows were noisier. Recent optimizations did not cause an E-core
regression; E-core still lagged Foundation because of journal CRC/recovery, typed
capture, and consumer formatting functional costs, not these optimizations.

Memory journal initialization previously zeroed in `Storage.createMemory`, again
in `format.initialize`, and additionally wrote zeros page by page; now the memory
backing keeps one complete writable zeroing, while header/checkpoint are written
through a zeroed entry; file/mmap still performed full zeroing that round. A 16.8
MB journal's batch runtime init median moved from 9.13 ms to 6.64 ms (5/5 pairs
lower), and sampled from 10.79 to 6.99 ms (intervals still overlapping); a 512 B
queue difference was below host noise. This was a local initialization-cost result,
not throughput or a cross-library ranking.

Fresh Linux mmap on ext4/XFS/btrfs/F2FS and similar filesystems that can prove
fresh extents read as zero changed to writing only header/checkpoint and relying
on `MAP_POPULATE` instead of whole-range zeroing and page-by-page writes; unknown
filesystems kept full zeroing, and Windows/Darwin kept prefault but switched to
read-only touches. A 16.8 MB journal's sampled/batch init median moved from
54.2/53.8 ms to 8.2/6.9 ms, with 5/5 pairs lower and non-overlapping medians; a
512 B queue difference was below noise. A 16 MiB ext4 probe on a new file and a
truncate-then-extend file both had zero non-zero bytes. This did not represent
steady-state throughput, durability, or non-Linux device qualification.

Raw data, failures/slow values, per-round source identity, and local before/after
results were retained in evidence at that time; earlier README performance
narratives are in [the historical snapshot](readme-before-reorganization.md).
Remaining work for the complete goal was tracked by
[current acceptance status](../implementation-status.md).
