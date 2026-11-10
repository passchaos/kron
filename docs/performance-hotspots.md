# Default redaction and journal CRC hotspots

Profiling complete million-record file workflows identified several concrete
costs. This page records the mechanisms and the local measurements that drove
the retained changes. Detailed measurement directories have been removed from
the repository; the conclusions below are historical notes, not a current
cross-library ranking.

## Default redaction scratch removal

When no redaction rules are configured, the older implementation still copied
fields/arguments and cleared four scratch arrays. In a CPU profile, roughly 36%
of samples landed in `redact.clearScratch`. The revised implementation first
runs the complete `ValueValidator`; with zero rules it hands the event directly
to the same encoding/submission function. With rules, it enters a separate
`noinline` function and keeps scratch alive only for that call. Secret
replacement, node/depth/cycle/duplicate-key validation, caller-input
immutability, and the deep copy before acceptance are preserved. In ReleaseFast
disassembly, the `submitDestination` stack frame dropped from `0xa858` to
`0x378`.

## Journal slot CRC

After removing the default scratch, roughly 37% of samples in a 70-sample
profile landed in journal slot CRC, covering commit, consumer peek, and release.
A pure-Zig IEEE CRC32 slice-by-8 implementation replaced only the v1/v2 slot
calculation without removing any check. The 20-byte header, v2 24-byte schema
reference, polynomial, and final XOR stayed unchanged; other header/checkpoint/
archive CRCs were untouched. Module tests covered 496 length/alignment
combinations, 1,984 segmented updates, 256 single-byte cases, and golden
vectors; Vort source interoperability also passed.

A five-run P4 complete-output comparison showed a local throughput increase, but
tail latency depended on background scheduling and the p99 of the
scratch-only variant rose. Faster producers also hit fixed-slot backpressure
more often, so a lower p50 was not treated as an overall win. A second set of
nine runs per configuration on six physical cores remained above the 10%
variability threshold. Both comparisons were **inconclusive**.

All 66 trials completed; 51 complete-output trials produced 510,000
accepted=written records with zero pending/drop and zero Runtime allocation
during measurement. The remaining 15 admission-only trials produced no output.
Small `perf` runs included initialization and cannot be treated as steady-state
hotspot shares. Host governor and kernel symbol policy were not changed.

## 2026-11-01 complete-workflow profile and CRC update

A new profile of the complete JSON file workflow used P4 SPSC-memory with one
million events, the same system clock, and written/shutdown endpoints. About 24%
of before samples landed in journal CRC: roughly 9% in producer commit and 15%
in consumer peek/reclaim. Each profile had about 1K samples; after the change,
the CRC update itself accounted for about 20% of samples. Different inlining
boundaries and total work mean profile shares cannot be converted directly into
speedups.

Changing the same CRC implementation to 16-byte slicing preserved the standard
IEEE protocol, checkpoints, and coverage while growing the read-only table from
8 KiB to 16 KiB. Five fixed-CPU primitive PMU pairs reduced user cycles by 24.4%
and increased instructions by 4.3%. This proves lower primitive cycle cost on
this host, not end-to-end throughput. A complete before/after workflow ran 120
trials and verified 12.12 million records, plus 10 long one-million-record
batches (10.01 million records); all logs were complete, but throughput and tail
latency remained inconclusive because of host noise. Slow values were retained.

## 2026-11-01 PCLMUL IEEE CRC

The complete JSON profile again placed journal CRC at about one quarter of
user-space samples, covering the three required checkpoints: producer commit,
consumer checked peek, and release. This round replaced only the block loop.
For x86_64 builds declaring PCLMUL+SSE2, it uses 4-lane 64-byte folding,
128→64→32 reduction, and a Barrett step. Generic x86_64, non-x86 targets, short
inputs, and tails under 16 bytes keep the original 16-byte slicing table. The
polynomial `0xEDB88320`, reflection, final XOR, all checkpoints, schema-reference
coverage, and journal/recovery format stayed unchanged. There is no runtime CPU
probe, allocation, or new external dependency.

CRC differential tests covered standard vectors, 64 alignments × 36 lengths,
and 32 alignments × 22 lengths × 14 incremental splits, comparing against
`std.hash.Crc32`. The portable fallback was re-verified with
`-mcpu=baseline`, aarch64 compiled, journal v1/v2 goldens stayed unchanged, and
Vort source interoperability passed while reporting `backend=hardware`.
ReleaseFast passed 81/81 steps and 503/503 tests; one crash writer that was not
READY within 10 seconds under host I/O pressure passed when re-run separately.

Journal-shape CRC primitive medians on a fixed CPU:

| Payload | Before ns/record | After ns/record | Change |
| --- | ---: | ---: | ---: |
| 64 B | 24.56 | 13.83 | −43.7% |
| 256 B | 95.23 | 18.98 | −80.1% |
| 512 B | 199.96 | 26.34 | −86.8% |
| 2 KiB | 785.42 | 79.56 | −89.9% |
| 16 KiB | 6312.29 | 535.23 | −91.5% |

Five fixed-CPU complete-workflow PMU pairs reduced SPSC-memory P4 user
instructions by 15.33% and async-memory P1 by 14.78%, with both-side spread
below 1.2%. SPSC-memory P4 complete throughput rose from 1.393M to 1.816M
records/s (+30.3%) and met this round's CV/spread threshold; async-memory P1
rose from 1.483M to 1.913M (+28.9%) but intervals still overlapped. One hundred
alternating complete-file trials verified 10.1 million JSON records, all
accepted=written with pending/drop=0; five throughput groups rose 15%–84% but
were all inconclusive under host load.

This is a compile-time path for native x86_64; generic and non-x86 targets keep
the portable table and do not receive the acceleration. Archived Foundation/
Quill numbers came from different source snapshots and host windows, so this
round did not establish a new cross-library ranking.

## 2026-11-01 decoded-delivery validation reuse

After PCLMUL CRC, the main remaining costs shifted to consumer decode and output
formatting. The encoder also ran a complete `ValueValidator` traversal over the
same tree the decoder had already validated. This round skips the second tree
validation only for events proven by the checked decoder:
`codec.decode`/`schema_codec.resolve` set an internal `Event.tree_validated`
flag after checking the wire tree, node budget, depth, duplicate keys, and
lengths; internal `encoder.common.encodeDecoded` selects the validated renderer
only for that flag and otherwise uses the public validation path.

Public `encoder.encode/encodeWithTime` always validates and ignores the hint.
Runtime first performs `codec.measure` or redaction/binding validation during
admission, then `submitSafeDestination` overwrites the caller-provided hint with
trusted context. Binary routes continue to use public validation. No unchecked
writer or reusable public credential is exported. Tests lock in that a forged
hint on a cyclic tree is still rejected by the public encoder with zero output,
that `runtime.submit` still returns `DuplicateKey` for duplicate keys, and that
decoded text/JSON/logfmt bytes match the public encoder.

Five fixed-CPU complete-workflow PMU pairs reduced SPSC-memory P4 user
instructions by 3.73% and async-memory P1 by 4.49%, with 0.5%–1.6% spread.
Cycles/task-clock remained inconclusive under host load. One hundred complete
file trials hit a 120-second mmap child timeout after 52 trials and 5.25 million
records; completed trials were all accepted=written with pending/drop=0 but were
not used as throughput qualification.

A follow-up that borrowed the schema `Definition` pointer to avoid a second
ready lookup increased SPSC-memory P4 and async-memory P1 user instructions by
0.68%/1.38% and was reverted. A `readHeader` prefix-reuse candidate changed
instructions by +0.40%/−0.07%, within noise, and was also reverted. Both negative
results were retained as evidence that visible duplicate work does not
automatically produce an end-to-end win.

## 2026-11-01 fused wire-to-JSON consumer path

After CRC and decoded delivery, the remaining consumer cost was dominated by
`decodeRecord` materializing `Event`/`Field` and then traversing the JSON tree
again. This round added a fused path for a common shape: current self-contained
v4 payload, exactly one JSON/text/logfmt route, non-deferred message, and no
format arguments; attributes may be scalar or nested, with nested descriptors
using a caller scratch arena. The fused renderer parses header/scope/message/
trace/source/attributes once and writes the same JSON/text/logfmt record as the
public encoder into caller scratch. Every value tag is validated by the checked
wire parser, and top-level keys are deduplicated before writing to the sink.
Corrupt payloads return the original decoder error; other shapes return
`error.Fallback` and use the original decode+encode path. Journal format, public
encoder, validation boundaries, and route semantics are unchanged.

Unit tests compared the fused output byte-for-byte with
`decode + encodeWithTime(.json)` for flat events (unsigned/signed/string/bool/
float/duration/timestamp/null, trace/span/source) and nested groups/arrays;
deferred messages confirmed `Fallback`. Complete `verify-local` passed 81/81
steps and 510/510 tests, including nested and text/logfmt fused validation. A
10,000-record SPSC-memory complete-file workflow produced 11,000 physical
records verified by an independent oracle. Five fixed-CPU PMU pairs reduced
SPSC-memory P4 user instructions by 5.94% and async-memory P1 by 6.20%, with
0.8%–1.2% spread; cycles/throughput remained inconclusive.

The path is intentionally narrow: legacy payloads, schema references,
template/args, multiple routes, and binary continue on the original path. Nested
attributes are supported. The public encoder still validates independently, and
the fused path writes to scratch only after the complete record is verified.

## 2026-11-02 checked wire typed visitor and inline scalar rendering

A complete shared Memory/Mmap P1/P4 profile at baseline `5b72254` verified 4.004
million JSON records. `wire.render` accounted for about 11.1%/5.0%,
`WireInput.value` for 3.4%/1.5%, and `valueInner` for 2.8%/1.5%; samples were
about 1K with zero lost. Profiles include initialization/cleanup and exclude the
kernel, so sample shares cannot be converted into exact cycles or throughput.

`WireInput.valueWith(receiver)` keeps the same tag, length, node, depth, nested,
duplicate-key, and arena-budget checks, then calls `receiver.accept` with a
comptime tag and typed payload. Public `value()` uses an internal materializer to
construct the original `Value`, so the external API and error set are unchanged.
Arrays/groups are still fully parsed before the callback, and callbacks cannot
observe partially validated aggregates. The fused JSON/text/logfmt
`ValueWriter` compiles scalar writes per tag, skipping intermediate `Value`
materialization and generic second dispatch. Schema kind masks are checked after
complete payload validation; malformed/truncated precedence and the rule that
only complete scratch records reach the sink are unchanged. Public value/event
APIs still fully validate borrowed trees; no unchecked writer, reusable
credential, or CRC removal was introduced.

An independent before/after module differential ran 17,527 comparisons over flat
all-scalar/UTF-8/bytes/extrema, nested, and maximum 256-node fixtures; 9,769
valid mutations matched byte-for-byte in JSON/text/logfmt, with the original
decoder and fused renderer as independent oracles. New tests confirm that
damaged bools, truncated integers, node budgets, and duplicate groups fail
before the callback with zero calls, while a valid complete group calls once.
Root Debug 20/20, Safe 59/59, and final Fast 60/60 passed; ReleaseSafe passed
151/151 steps and 640/641 tests (one system-local capability skip), including
source distribution, nine target objects, real SIGKILL, and examples.

The first typed-writer version generated multiple outlined calls and reduced
instructions by only about 0.15% in 40 complete PMU trials, with no cycle/speed
qualification. After switching to comptime-tag inlining, 40 complete shared
real-file trials verified 12.04 million JSON records and reduced user
instructions by 1.686%/1.664% for Memory P1/P4 and 1.652%/1.656% for Mmap P1/P4,
with CV/spread and non-overlapping median intervals. Cycles and written speed in
that PMU window still overlapped, so this is not a general throughput/latency
claim. Eighty uninstrumented workflow trials verified 24.08 million JSON records
with mixed throughput; 20 P4 sampled rechecks verified 6.02 million records
(Memory −0.12%, Mmap +2.85%, still inconclusive). The `valueInner` code size grew
from about 0x641 to 0xfbc as part of the candidate trade-off; inlining is not
assumed to always be faster.

## 2026-11-02 direct JSON metadata tag writes

After the typed visitor, JSON metadata still wrote timestamp, session, sequence,
route_mask, and config_generation through temporary unions such as
`valueInner(writer, .{ .unsigned = event.session }, .json)`. That path placed
`u64` into `Value.unsigned: u128`, then went through a runtime tag switch and
wide-integer decimal formatting, adding five generic dispatches and u128
instances per JSON record.

The candidate called internal `writeTaggedValue` directly with a comptime tag
and the original `i64`/`u64` payload for those five fields. JSON precision,
quoting, decimal output, escaping, public API, wire protocol, and error
boundaries stayed unchanged; text/logfmt metadata already used direct
`decimal.write`. No allocation, dependency, or per-emit work was added, and
public value/event validation was unchanged.

In 30 alternating encoder-probe PMU trials, JSON instructions/cycles medians
fell 2.58%/1.93%, and scalar5/nested20/wide5 ns/record fell 2.60%/1.75%/1.55%,
with CV/spread and non-overlapping medians. Complete output checksums/bytes
matched for all three formats. The text/logfmt control instructions were
essentially flat; their cycle differences were retained as binary-layout/
measurement-window controls, not as claimed improvements or regressions.

Forty complete shared real-file trials verified 12.04 million JSON records and
reduced user instructions by 2.445%/2.463% for Memory P1/P4 and
2.460%/2.479% for Mmap P1/P4, with CV/spread and non-overlapping medians.
Cycles overlapped in all groups; written speed in the same window was Memory P1
+1.42% (overlap), Memory P4 +4.13% (non-overlap), Mmap P1 −1.06% (overlap), and
Mmap P4 +3.48% (non-overlap). Eighty uninstrumented workflow trials verified
24.08 million JSON records; all eight written-throughput groups were positive
(+0.95% to +5.55%), six met the noise threshold, and Memory/Mmap P4 batch
medians did not overlap. Sampled p50 was flat; p99/p999 mostly fell but intervals
still overlapped, so no general tail-latency promise is made.

## 2026-11-02 JSON severity fixed literals

The JSON encoder previously wrote `,"severity":` and then ran `quoted` over
`@tagName(event.level)` for every record. The candidate selected one complete
literal per `Level` and wrote it once; `err` still emits `"err"`, and text/logfmt
are unchanged. In 30 encoder probes, JSON instructions fell 2.05% while
text/logfmt control instructions stayed flat. Forty complete shared trials
verified 12.04 million JSON records and reduced Memory/Mmap P1/P4 instruction
medians by 1.68%–1.70%, with CV/spread and non-overlapping intervals. Eighty
workflow trials had mixed throughput (Memory P1 batch +6.35%, P4 sampled
−5.91%, Mmap P1 batch −1.37%, and others), so this is not a general throughput
gain.

## 2026-11-02 Memory journal single-zero initialization

The Memory journal previously zeroed memory three times:
`Storage.createMemory` did a full `@memset`, a per-4096-byte volatile zero loop
followed, and `format.initialize`/`initializeV2` zeroed the full range again.
The candidate removed the per-page loop, kept one complete writable zeroing of
the memory backing, and added `initializeZeroed`/`initializeV2Zeroed` that write
only the header, identity, CRC, and checkpoint. File/mmap paths keep the full
zeroing entry point so stale bytes in a reused mapping cannot be mistaken for a
valid slot payload.

`init_probe.py` used async Memory, a file sink, 256 slots, and
`max-record-bytes=65536` (about a 16.8 MB journal), with five alternating
before/after pairs. Batch runtime init median fell from 9.130 ms to 6.638 ms
(5/5 pairs lower, ratio 0.565–0.739) with non-overlapping bootstrap intervals;
sampled median fell from 10.793 ms to 6.992 ms, with 4/5 lower but overlapping
intervals. For a 512 B queue (about 147 KB), the removed zeroing was below host
noise: five pairs were mixed and all intervals overlapped, so neither a
regression nor a gain is claimed. File/mmap initialization paths and all
CRC/slot/recovery protocols were unchanged; ReleaseSafe passed 151/151 steps and
641/642 tests (one system-local capability skip).

This optimization proves only a local reduction in Memory journal initialization
cost; it does not establish producer/consumer throughput, Mmap startup, or a
cross-library ranking.

## 2026-11-02 Fresh Linux mmap header-only initialization

Fresh mmap previously ran `@memset` over the entire mapping and wrote the same
byte per page in `Mapping.open`, dirtying every page, so publication/fsync had to
write back the whole journal. Linux `map` already used `MAP_POPULATE`; after
`setLength` + `fallocate`, fresh files on ext4/XFS/btrfs/F2FS and similar
filesystems provide read-as-zero unwritten extents. The candidate writes only
the header/identity/CRC/checkpoint on those filesystems and keeps full zeroing
for unknown filesystems. Windows/Darwin keep prefaulting but use volatile reads
instead of needless dirty pages, and `freshZeroed` returns false.

An ext4 zero probe read every byte of a fresh 16 MiB file and of a file that had
4 KiB written, was truncated to zero, and extended again; both had zero non-zero
bytes. `mmap_init_probe.py` used async Mmap, a file sink, 256 slots, and 64 KiB
records (about a 16.8 MB journal) with five alternating pairs: sampled init
54.212 ms → 8.227 ms (0.152), batch 53.809 ms → 6.948 ms (0.129); 5/5 pairs
lower with non-overlapping median intervals. A 512 B queue showed 0.945/0.961 ms
medians with overlapping intervals, below noise. This proves only a local
reduction in fresh mmap initialization cost, not producer/consumer throughput,
steady-state Mmap, durability, or a cross-library ranking. Non-Linux device
qualification is still missing.

## 2026-11-01 schema fusion after batch coalescing

A profile at baseline `366adc3` verified 6.006 million physical records across
six one-million-record complete JSON groups. SPSC Memory inline consumers used
about 52% of user-space core-cycle samples; prepared SPSC Memory still had about
11% in `decodeRecord` including children and about 15% self time in `memcpy`,
which also includes producer copies. Shared Memory `begin` had significant
samples as well. Profiles include setup/preparation/cleanup and exclude the
kernel, so these shares cannot be converted directly into throughput or a
specific lock attribution.

The current schema consumer renders directly from canonical definitions and
values when at least 64 records are ready, with a single JSON/text/logfmt target
and no deferred messages/arguments, avoiding top-level `Field` materialization
and a second attribute traversal. Short windows, template arguments, multiple
routes, and binary keep materialized resolve, and the same record reuses the
canonical lookup. Type masks, nested nodes/depth/arena, lengths, schema identity,
and original error precedence are preserved. On the cold error path where output
scratch is insufficient, the original `reference.resolve` runs first so later
corruption is not hidden by a record-too-large error; the sink is called only
after all rendering succeeds. Per-record CRC, old-configuration pins, output
barriers, and checked reclaim remain.

Three-format all-tags/source/trace/static/dynamic/nested/readable-time and
historical v2 comparisons, 4,096 mutations, all truncations, and scratch guards
passed. A real-runtime matrix of Memory/Mmap × shared/SPSC × 1/64-record windows
× 16/512-byte output × three schema corruption cases (48 scenarios) confirmed
zero sink output, original errors, and all pending/pin state; related Debug/Safe/
Fast tests passed 26/26. A final 240 complete-file trials verified 24.24 million
JSON records; prepared Memory P4 shared/SPSC throughput medians rose 6.35%/8.03%
with CV/spread and non-overlapping medians, while most Mmap groups and tail
quantiles were unqualified. Forty complete PMU trials verified 12.04 million
records: schema SPSC Memory/Mmap instructions fell 1.804%/1.802% and shared
Memory fell 1.906%, with both-side spread below 0.14%; inline control
instructions rose 0.171%. Another 20 one-million-record P1 trials verified 20.02
million records; final Memory/Mmap negative medians of 0.65%/1.39% overlapped,
so no overall P1 improvement is claimed.

The native `drainJournal` explicit stack frame reservation grew from 37,800 to
40,712 bytes (+2,912), excluding push/callee/recursion totals. Heap/journal/file
budgets did not increase. Earlier P1 negatives from the full-window schema
fusion, the rejected header-pointer version, and 187 interrupted-capture runs
were retained separately; they are not part of the final qualification. The
current data does not provide a new Foundation or io_uring ranking.
