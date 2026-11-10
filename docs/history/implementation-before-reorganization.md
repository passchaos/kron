> Historical snapshot before reorganization; source baseline `7e98358`. See
> [documentation navigation](../README.md) for the current interface and status.
> Detailed measurement rows and links to removed evidence directories are omitted
> from this English translation.

# Implementation acceptance checklist

This file tracked actual completion evidence for the
[overall design](../design.md). Items without execution, fault-injection, or
source-review evidence remained incomplete; type declarations or documentation
were never accepted in place of behavioral verification.

The then-current scope was single-machine logging on
Windows/Linux/macOS/Android/iOS. Network sinks, HTTP/TLS collectors, OTLP
exporters, and their tests/build entries had been removed. Historical gate counts
describe only their source revision; current capability is determined by the
current gates.

## Current single-machine gates at this snapshot

System local time used consumer-side formatting and per-second caching: explicit
`.timestamp = .{ .zone = .local }`, with producers still capturing only Unix
nanoseconds; cross-second/backward jumps refreshed, and DST followed system
rules. Eight groups (Memory/Mmap × shared/SPSC × inline/schema) verified zero
producer conversions, one consumer conversion per 96 same-second records, and no
allocation after Runtime initialization. An independent zoneinfo oracle checked
372 timestamps across six timezones × five modes plus recovery; changing the
timezone on recovery was rejected and the original journal was unchanged. The
complete ReleaseSafe gate passed 109/109 steps with 576 tests passing and one
local-cache test skipped by capability in a no-libc build. Local-time
specialization and oracle actually ran, and nine-target object compilation passed
10/10. Independent package local/single-threaded options passed; local formatting
verified 70 samples/7 million records by hash. No complete throughput or
cross-library ranking was derived from these local results.

The application-impact benchmark used identical deterministic compute/cache work
with no logger, shared Memory, SPSC Memory, shared Mmap, and SPSC Mmap, covering
P1/P4/P16, per-request or sparse logging, five repetitions, 300 trials, 3.6
million application requests, and 1.65756 million complete JSON records. An
independent Python model checked per-worker state computation and logged results;
all output/identity/FIFO checks and zero post-initialization Runtime allocation
passed. Complete application throughput groups remained inconclusive because of
variance; PMU coverage was at least 91%, and some CPU-work differences had local
qualification. The synthetic workload did not replace real-service/cold-cache/
durable or cross-library verification; P16 oversubscribed the six-core mask, and
`every=16` concentrated the log source on producer 0. Interface tests, oracle
negative tests, 15 smoke cases, and the complete ReleaseSafe gate passed 97/97
steps and 559/559 Zig tests at source `6e774b0`.

Prepared measurement reuse passed 93/93 ReleaseSafe steps, 556/556 Zig tests, and
10/10 nine-target ReleaseSafe object compilation, including independent five-mode/
single-threaded/source-distribution packages, configuration/filter/lifecycle/file
faults, random SIGKILL, and wire/schema corruption matrices. Formal 380 trials/
64.38 million records, node counts, 4,096 old/new codec differentials, extra
submission stack frames, and P1 extreme-quantile negatives were bound to that
round's source. Stable complete performance, business/durable baselines,
long-running fuzz, and other-platform device execution remained open.

Prepared non-redacted submission reused dynamic value/nested-key bytes obtained
from the full-tree validation in the same unchanged call, while canonical shape/
level/reference, queue full/fallback, and capacity boundaries were preserved. The
public reference codec still fully validated, internal implementation moved to
`reference_encoding.zig`, and no external measured entry existed. Real Memory/Mmap
shared/SPSC, predicate/tree, full/drop/fallback, oversized/level, redaction, and
forged binding/hint tests passed 64 each at Debug/Safe/Fast; 4,096 old/new codec
differentials matched; public Runtime node counts moved from 8 to 4. Formal 380
complete-file/PMU/one-million-record comparisons verified 64.38 million JSON
records; schema SPSC Memory/Mmap and shared Memory P1 user instructions fell
3.99%/3.97%/4.33% with CV/spread and non-overlapping intervals; shared Memory P1
one-million-record batch throughput median improved 4.89%. P1 long sampled p99.9
median moved from 1,017 to 15,974 ns, a clear negative with variance above the
threshold; most other throughput/tail groups did not qualify, and all limits/slow
values were retained.

A candidate that merged schema shape checks into the size visitor was tested and
rejected: 4,096 independent module differentials against frozen old source (342
successful byte matches, 3,754 rejection/error/no-write matches), Safe 63 tests,
and Debug/Fast 29 tests passed. Four hundred complete-file/PMU trials verified
56.4 million JSON records; the first 40 PMU trials had potential test-end
overlap, and the formal clean 360 trials verified 44.36 million records.
Independent PMU schema SPSC Memory/Mmap instructions rose 0.463% by median with
non-overlapping intervals, complete 320-trial throughput was entirely
inconclusive, and most schema P4 medians were negative. No general gain was
obtained; production restored `cd00f1f` and retained the original 552-test/
nine-target qualification.

SPSC local-queue space notification passed 93/93 ReleaseSafe steps, 552/552 Zig
tests, and 10/10 nine-target object compilation; related Debug/Safe/Fast tests
passed 25 each, and external Memory/Mmap SPSC shutdown/worker-error tests passed
2 each. Real shutdown before wait, epoch wrap, own-abort reclamation, and
cross-queue worker-error broadcast lost no wakeups, while shared producer/control
kept the original global protocol. Formal 400 complete-file/PMU/one-million-record
comparisons verified 84.40 million JSON records, plus 24 diagnostics/2.424 million
records; Memory inline SPSC P4 long sampled p99.9 median moved from 366.312 to
340.708 µs (−6.99%) with CV/spread and non-overlapping intervals. Ordinary
throughput, p50/p99, and most Mmap groups did not qualify; a short Memory P1
negative median around −10% was retained and did not reproduce in long P1 batch;
each Journal in-process object grew 64 bytes without increasing allocation counts
or queue/file backing.

A cross-queue 64-record round-delivery candidate was tested and rejected: real
four-queue Memory/Mmap × inline/schema, sparse tracking capacity, peek/flush/
durable/late-reclaim corruption, and original peer service positions passed
Debug/Safe/Fast 26/26 each; 440 complete-file/PMU/single-quantum control trials
verified 52.44 million JSON records. p99.9 median fell, but p50/p99 clearly
regressed, most throughput groups were negative, and all complete performance
qualification remained inconclusive; four instruction groups rose 0.58%–0.71%,
and the added scheduling/cross-source acknowledgement and stack space produced no
overall gain. Production restored `714c470/e8bd353` and retained the existing
scheduling/API and 549-test qualification.

The historical Foundation + spdlog comparison used frozen Foundation's real C++
spdlog frontend and Rust release backend in 200 same-round trials, verifying 20.2
million JSON records across Memory/Mmap shared/SPSC, P1/P4, inline/schema, and
sampled/batch; kron actually selected portable, accepted=written, and pending/
drop=0. Ordinary inline SPSC complete-throughput medians were 8.67%/3.21%/
23.09%/12.58% above Foundation in four groups, while shared Memory P4 was still
4.41% behind; through-shutdown cross-library groups remained inconclusive because
spread exceeded the threshold. Most schema configurations were slower, SPSC p99.9
and Mmap init/lifecycle were still behind, and Foundation's 806 ms/234 ms Memory
shutdown slow values were retained. The comparison harnesses and evidence are no
longer tracked; this remains a historical snapshot and did not establish an
industry-fastest or stable overall lead.

Admission View transfer passed 93/93 ReleaseSafe steps, 549/549 Zig tests, and
10/10 nine-target object compilation, including independent five-mode/
single-threaded/source-distribution packages, Linux host qualification,
configuration/deadline/error/old-new wire matrices, and 12 real random SIGKILL
recovery scenarios. Ordinary shared admission reused the validated configuration
View obtained at `begin` and released the reader at `end`; accepted journal
records retained an independent pending pin before commit, while SPSC/control/
deadline kept the original protocol. Three new real Runtime tests locked in
Memory/Mmap reader/pin differences, concurrent replacement old leases being
protected before reserve and after worker ACK, and accurate release on filtered/
sampled/capture/sync errors; old filter-overlay and SPSC cache regressions
remained, with related Debug/Safe/Fast tests passing 15/15 each. Formal 320
complete-file, 40 PMU, and 10 independent one-million-record trials verified 54.37
million JSON records; shared schema Mmap P1 long workflow median moved from
1.746M to 1.829M records/s (+4.79%) with CV/spread and non-overlapping medians;
most P4/other groups did not qualify, PMU shared Memory P4 had a −3.36% negative
median with non-overlapping intervals, and all slow values/tail quantiles were
retained.

A candidate that rendered directly into the file buffer was tested and rejected:
33 related Safe and 17 Debug/Fast targeted tests passed, covering complete prefix
transactions, short writes/zero progress/disk errors, three formats/binary/
templates, invalid input, and zero allocation; 280 complete-file/PMU trials
verified 36.28 million JSON records. Four instruction groups rose 0.48%–0.64%,
complete throughput medians overlapped, and several Memory paths were negative;
the extra callback interface was not adopted, and production restored `c2f8792`.

The final schema-fusion source passed 93/93 ReleaseSafe steps, 545/545 Zig tests,
and 10/10 nine-target object compilation, including independent five-mode/
single-threaded/source distribution, Linux host qualification, old/new wire
matrices, real random SIGKILL, and file/lifecycle negative gates. When TSC
hardware calibration was unstable, the run actually fell back to native and
passed its safety gate; fallback was not described as a new TSC acceleration
qualification.

The schema-fusion consumer covered at least 64 ready records, a single JSON/text/
logfmt target, and schema records without template arguments; short windows kept
the original materialized path, canonical definitions were reused per record, and
type masks, nested nodes/depth/descriptors, lengths, schema identity, and the
original decode-before-route error order were preserved. When output scratch was
insufficient, the cold path completed the original reference decode so later
corruption was not hidden by a record-too-large error. Forty-eight real Memory/
Mmap × shared/SPSC × 1/64-record windows × 16/512-byte scratch × three schema
corruption scenarios confirmed zero sink output, original errors, and all pending/
pin state; three-format all-tags/static/dynamic/source/trace/nested/readable-time/
historical-v2 byte comparisons and 4,096 mutations passed; related Debug/Safe/Fast
tests passed 26/26. Final 240 complete-file, 40 complete-PMU, and 20
one-million-record P1 trials against `366adc3` verified 56.3 million physical JSON
records; Memory prepared P4 shared/SPSC throughput medians improved 6.35%/8.03%
with CV/spread and non-overlapping medians; schema instructions fell 1.8%–1.9% by
median while inline control instructions rose 0.171%. Most Mmap groups and tail
quantiles remained inconclusive; final P1 long-workflow Memory/Mmap negative
medians of 0.65%/1.39% overlapped. Native `drainJournal` explicit stack
reservation grew 2,912 bytes; heap/journal/file budgets did not increase.

Ready-record coalesced delivery kept the original 64-record service quantum
budget 1..4, merged up to 256 contiguous ready records within the current
remaining budget without waiting to fill, kept at most 64 configuration groups,
and preserved per-record CRC/schema/old-route pins and post-output checked
reclaim. Real Runtime tests covered Memory/Mmap × shared/SPSC × inline/schema; 255
records all output at the first barrier with zero post-initialization allocation;
initial late corruption produced zero output; mixed old/new configuration final
flush/durable failure retained all 255 records and 150/105 pins; reclamation-time
corruption acknowledged only 190 and retained 65 old pins. Budget/coalescing
Debug/Safe/Fast tests passed; complete ReleaseSafe passed 93/93 steps and 540/540
tests, including real SIGKILL, independent five-mode/single-threaded/source
distribution, and Linux host self-check; nine-target ReleaseSafe objects passed
10/10. Two new child-QEMU shutdown schema ACK31/inline ACK3 recoveries passed on
Linux 6.8/ext4 only. Four record-tracking arrays grew from 5,440 to 21,760 bytes
locally, adding 16,320 bytes of consumer stack; configuration-group and heap/
journal/file budgets did not increase.

Portable 160 trials and independent io_uring 80 complete-file trials against
baseline `45f5ec1` verified 24.24 million physical JSON records with
accepted=written and pending/drop=0, preserving the system wall clock, complete
fields, and written flush/shutdown/cleanup endpoints. Portable Memory P1/P4
shared medians improved 4.44%/6.90%, SPSC improved 5.78%/9.97%, four groups passed
CV/spread, and the last three had non-overlapping bootstrap medians; most Mmap
groups remained inconclusive. io_uring P4 Memory shared/SPSC medians improved
14.18%/23.62%, two groups passed CV/spread with non-overlapping intervals; Mmap
did not qualify. Shared Memory io_uring p99 median moved from 22,459 to 34,674 ns,
a repeatable negative, while portable shared P4 tail negative medians remained
inconclusive.

Earlier `c4b7f34` portable/io_uring same-binary comparison completed 160/160
trials and 16.16 million physically verified JSON records: Memory/Mmap, shared/
SPSC, and P1/P4 each ran five sampled/batch repetitions, all explicit io_uring
requests actually selected `linux_uring`, and accepted=written with pending/drop=0.
io_uring median throughput was about 17%–19% lower on that workload; six of eight
batch groups passed two-side CV/spread and two were inconclusive, and all slow
trials were retained. The checked-batch confirmation boundary limited I/O overlap
and could not be generalized to every workload.

A conditional progress-wake candidate was not adopted: the concurrent-window test
after registering a waiter passed, and all 160 logs were correct, but several
shared-queue throughput medians were negative and bootstrap intervals overlapped,
so no gain was established. Saturated tracing showed no reduction in total futex
counts, indicating real waiters remained; production restored the original
notification. A real regression was retained for Memory/Mmap full-SPSC waiters
being woken on worker write failure, returning the original error, and leaving two
accepted records pending.

Linux/Android cold Mmap publication omitted the duplicate `msync` before
whole-file `fsync` while retaining file/parent-directory `fsync`; other platforms
kept the original mapping flush and explicit strict-durable protocol. Linux 6.8
kernel and ext4 synchronization sources confirmed coverage; file/directory
publication failure regressions verified initialization failure and lock release,
and schema directory failure remained unready without consuming a reservation.
Real child-QEMU/ext4 schema ACK17/31 and inline ACK3 force-kill recovery passed.
One hundred sixty Memory/Mmap complete-file trials verified 16.16 million records,
all accepted=written with pending/drop=0; call tracing showed `msync` 5→0,
`fsync` still 10, and `fallocate` still 5. Initialization/throughput were all
inconclusive; shared Mmap negative startup medians and SPSC positive medians, plus
all slow values, were retained. Final Safe passed 89/89 steps, 532/532 tests, and
nine-target ReleaseSafe objects.

An earlier Memory/Mmap-only same-round comparison at `182fc9e` with default
budget 4 compared Foundation's real spdlog frontend + Rust backend against kron:
120/120 trials and 12.12 million physical JSON records verified, accepted=written
with pending/drop=0. Including shutdown, Memory P1/P4 medians in M records/s were
Foundation 1.932/1.990, kron shared 2.136/2.063, and SPSC 2.151/2.106; Mmap was
Foundation 1.789/2.097, shared 2.107/1.741, and SPSC 2.157/1.911. Memory medians
led, Mmap P4 was still behind, and all Foundation throughput groups exceeded the
variance threshold, so no stable lead in both modes was claimed. Mmap SPSC P4
initialization median was 368 ms and full lifecycle 446 ms, versus Foundation
13 ms/62 ms; slow values and tail quantiles were retained.

The Memory/Mmap consumer batch budget exposed
`consumer_batches_per_queue=1..4`, defaulting to 4 and failing invalid budgets
before allocation. Deterministic real background tests across both storages and
shared/SPSC peers verified peer service positions 1/65/129/161 for budgets
1/2/3/4, preserving FIFO, written, zero residual backlog, and zero
post-initialization allocation; public tests observed a real futex wait on a full
SPSC queue, and shutdown correctly woke and aborted the unfinished reservation. A
fixed-batch default candidate verified 160 complete-file trials/16.16 million
records; p99.9 improved but p99 clearly regressed and throughput did not qualify,
so it was not promoted to default. A same-binary default-4/explicit-1 comparison
verified another 40 trials/4.04 million records: Memory p99 median 10.9→82.8 µs
and p99.9 about 377.7→114.7 µs; Mmap 9.1→84.5 µs and 391.0→110.7 µs, all
inconclusive with all slow values retained. Current Safe passed 89/89 steps,
530/530 tests, and nine-target objects.

Static scalar capture counted comptime scalar types as nodes, while dynamic
Value/containers/prefixes remained fully validated; Runtime still validated the
final tree after clock callbacks, and a new shared/SPSC clock-created cycle test
confirmed no reservation was consumed. Length accumulation changed to a u64 with
each item clamped to `u32_max+1`, returning `TooLarge` only after complete
validation; 8,192 arithmetic differentials and maxInt(usize)/cycle/duplicate
precedence passed. The combined scheme reduced complete PMU SPSC P4/shared P1 user
instructions by 3.00%/3.32% by median, static-only by 2.68%/2.97%, with spread
passing; the two versions ran 40 PMU trials/12.04 million JSON records. Formal 100
file trials verified 10.1 million records; all throughput was inconclusive and
several medians fell. Another 20 long sampled trials verified 6.02 million
records; SPSC p99 median moved from 1,051 to 10,143 ns and p99.9 from 360,195 to
420,294 ns, variance failed the threshold, and all negative data was retained. No
throughput or tail-latency gain was claimed. Final Safe passed 89/89 steps, 527/
527 tests, and nine-target objects.

Batch configuration record-pin optimization was tested and rejected: two
candidates ran 100 complete-file and 20 PMU trials, for 240 trials and 32.24
million physically verified JSON records, all correct, but neither qualified for
a complete-throughput improvement; several negative medians and high spread were
retained. Production configuration/delivery modules stayed at `8a351c0`. A
shared/SPSC late-reclamation corruption regression was retained: written=1,
pending=2, and after releasing the check View and SPSC cache the remaining record
pins still blocked old-lease reclamation, with destroy releasing exactly once.
Final batch-targeted tests passed 18/18 at all three optimization levels.

Native number output wrote directly into the existing Writer buffer: when at
least 21 bytes remained, it computed the exact digit count and wrote it, updating
only the actual end; a separate helper avoided expanding recursive value
rendering, and short buffers/streaming/wide values kept the bounded stack
fallback. Public encoder behavior was preserved for 12 complete records, 16,486
fixed prefixes, 49,494 generic prefixes, and new internal-buffer physical
short-write prefixes; Safe public time/configuration/predicate/file tests passed
30/30, and final complete ReleaseFast passed 89/89 steps and 522/522 tests. One
hundred complete-file trials verified 10.1 million logs; five throughput medians
improved 3.0%–4.0% and met this round's CV/spread, with SPSC Memory P4 having
non-overlapping medians and the rest overlapping. Another 20 long workflows
verified 6.02 million records: SPSC P4 user cycles fell 4.99% and instructions
rose 1.00%; a very slow producer sample kept long-workflow throughput
inconclusive, and all results were retained.

The `4447fe6` complete-file workflow compared Foundation's real spdlog frontend/
Rust backend, standalone spdlog 1.17, and kron: 140/140 formal trials and 14.14
million physical JSON records verified, accepted=written with pending/drop=0.
Including shutdown, P1/P4 medians in M records/s were Foundation Memory 2.116/
2.309 and Mmap 1.800/2.079, spdlog 1.640/0.673, kron SPSC Memory 2.174/2.108 and
Mmap 2.251/2.117; shared groups and stages were stored separately. kron's medians
were above standalone spdlog, P4 Memory was still about 9% behind Foundation, P4
Mmap differed by less than spread, and SPSC Mmap full lifecycle was about 107 ms
versus Foundation 58 ms. Standalone spdlog and some Foundation groups exceeded the
10% threshold, so a quiet-window cross-library lead was still unqualified.

Regex matching moved BOL/EOL epsilon/assertion expansion into configuration
compile time and used two 64-bit active bitmaps at runtime, traversing only states
that consume bytes; 128-state/32-depth/8 KiB-input limits, arbitrary bytes,
nullable loops, strict anchors, and independent state ranges across multiple
regexes were preserved. The final scheme passed 1,004,626 ReleaseSafe
coverage-guided runs (4,510 unique) in a temporary complete source copy; the main
source passed 89/89 ReleaseSafe steps, 520/520 tests, and Debug/Fast public
targeted tests 13/13, plus 1,006,557 coverage-guided runs. Eight business input
classes and two complete synchronous JSON paths ran five child-process pairs with
five repetitions and fixed CPU affinity; 900 sample inputs/matches/written/JSON
hashes all matched, but every final group was inconclusive because spread
exceeded the threshold. Native x86_64 `Pattern` grew from 4,624 to 9,264 bytes and
`Predicate` from 17,952 to 25,632 bytes, increasing fixed configuration memory and
compile cost.

Regex boundaries were completed: compilation/matching moved to
`src/pipeline/regex.zig`, field rules/configuration strings stayed in
`pipeline/predicate.zig`, and the public Pattern/Regex aliases plus original
128-state/32-depth/8 KiB input budgets were preserved. The first `]` in a
character class and control/two-hex-digit escapes were fixed; unsupported classes/
assertions/backreferences/unknown letter escapes explicitly returned
`UnsupportedRegex`, and direct anchor quantifiers or malformed hex returned
`InvalidRegex`; UTF-8 byte orientation, `.` excluding LF, and strict `$` end were
locked by the oracle. Eight seeds produced 161,872 results (161,504 independent
Python bytes comparisons) with exact agreement.

Route filtering derived inherited level masks at configuration publication and
kept independent scope filters checked per route; each generation added 64 bytes
without hot-path atomics/allocation and without changing wire format or recovery
fingerprints. 2,940 internal comparisons, public sync/shared/SPSC delivery across
64 routes, filter-only and full replacement, old snapshot retention, and channel
cache refresh passed. Related Debug 1/1, ReleaseSafe 15/15, ReleaseFast 13/13, and
native host gates passed; final nine-target ReleaseSafe objects and public
route-filter tests passed. 225 enabled-only pairs matched checksum/budget; eight
routes were about 12%–18% cheaper locally; 40 public admission/full trials
confirmed 200,000 written/pending 0/allocation 0, while complete throughput and
p99 remained inconclusive.

The decoder compatibility matrix covered eight inline/reference, current/
historical, scalar/nested, and deferred-template input classes. Each optimization
level ran 16,384 mutations, 2,382 byte truncations, and 128 short-scratch
capacities; 9,319 valid mutations passed borrow-range, complete-tree budget,
exact re-encoding, and JSON checks. After schema definition CRC/hash refresh, 54
structural corruptions were rejected and 93 valid definitions rechecked canonical
hashes; eight real files were exported twice read-only through Reader. Debug/
ReleaseFast independent matrices passed 3/3 each, and ReleaseSafe fuzz/query
passed 30/30.

The independent Zig package added target-host self-check `qualify DIRECTORY`,
whose test logic can run directly in a Zig mobile host without Python or a
subprocess. Linux normal/single-threaded ReleaseSafe and normal ReleaseFast ran
five modes or sync, zero post-initialization Runtime allocation, Unicode file
names, ordinary/schema journal close-reopen and exclusive locking, read-only
inspection, rotation retention, and actual durable capabilities; locally fetched
source distribution passed the same checks. Two independent package tests passed;
an existing acceptance directory was rejected for reuse with output unchanged;
the root `test-platform-host` gate passed 2/2 steps, a Windows PE including this
entry linked, and the other four platform device runs were still missing.

Pre-registered schema encoding merged complete-tree validation and length
accounting and wrote through a shared internal wire writer, validating each node
once per reference size/encode; the public value writer continued independent
validation. Four boundary/count tests passed; ReleaseSafe 41 encoding tests, 31
external encoding/dual-storage/query tests, and real crash gates passed; final
nine-target ReleaseSafe objects and encoding benchmark input tests passed. All
450 fixed-affinity before/after pairs matched checksum, byte counts, and budgets;
local reference-length computation fell about 23%–44%, nested reference encoding
about 29%, and other reference encodings remained inconclusive because of noise.

Random runtime process termination was added: two producers, shared/SPSC, and
ordinary/schema (four combinations) submitted and wrote normally after READY, then
were SIGKILLed at seeded times. Formal ReleaseSafe/ReleaseFast `test-runtime-crash`
passed 12 scenarios each and six negative oracle tests; another 32 ordinary seeds
and eight u64-boundary seeds confirmed 109,419 complete ACKs were covered by
output/recovery, with duplicates and incomplete reservations observed. The
2026-11-01 complete gate also actually hit a 1,950-byte incomplete JSON tail,
confirming it was a prefix of a complete journal-recovered record.

The public interface remained Zig-only. Independent consumer projects imported
through `b.dependency("kron")` and `dependency.module("kron")`, and ReleaseSafe
actually ran sync/memory/mmap/SPSC-memory/SPSC-mmap, checking JSON, deep copy,
redaction, reload, written/pending, and file counts; single-threaded consumption
confirmed only one OS thread on Linux and rejected async mode before creating
files. A source archive formed through local `zig fetch` according to ZON
`.paths` also passed independent five-mode execution. A Windows x86_64-gnu
independent application linked as a PE, with no device execution qualification.

`zig build verify-local -Doptimize=ReleaseFast -j2 --summary all` passed **81/81
build steps and 498/498 Zig tests**, plus 15 Python regression-tool tests, six
recovery-oracle negative tests, four C++ workflow report negative tests, 17
negative compilations, 4,096 regex differentials, six real SIGKILL recovery
scenarios, six Memory/mmap exit-and-drain scenarios, ten seeded recovery
campaigns, 12 random runtime SIGKILL scenarios, independent Zig five-mode/single-
threaded consumption and native platform self-check, seven fuzz tests including
the version matrix, and nine example compilations. The independent single-
threaded executable verified real JSON files, field selection/redaction, reload,
durable file flush, shutdown, and no post-initialization Runtime allocation.

Default context-free loggers captured directly into the final descriptor array,
with static structs/tuples reserving stack space by actual field count up to 64;
child contexts kept the original merge. Named structs had compile-time unique
internal keys, while old prefixes/dynamic keys/nested values were still validated
with the shared node budget and original error precedence. Six new public capture
regressions and comparison-count tests passed; 45 fixed-session log pairs matched
checksum/bytes/counters exactly. Five/ten-field synchronous JSON narrow medians
fell about 11%/21%, but the real SPSC async comparison remained inconclusive.

File reliability fixes: ordinary rotation had no implicit fsync/strict durable;
explicit sync confirmed current and tracked retained archives and reported a
missing archive; external reopen to an unknown target directory revoked historical
durable qualification while written continued; `UnsupportedDurability` was not
latched as an ordinary write fault, while real I/O errors still latched. A retired
configuration with zero pending and completed required written could be reclaimed
when extra durability was unsupported, withdrawing global historical capability;
`InputOutput` retained the lease for retry. Nine rotation reliability/resource
tests, six real partial-write FileSink tests, and two collection tests passed.

Seeded SIGKILL campaigns passed ten default cases and eight high-u64 seeds,
covering 16-slot 4–7 wraps, two configuration switches, cross-generation pending
records, ordinary/schema payloads, nested/source/secret, and CRC; repeated
inspection kept journal/output hashes unchanged. The randomization covered
workload and epoch boundaries at an exact READY point, not arbitrary-time faults
or physical power loss.

Public codec validation and length accounting merged into one `ValueValidator`
traversal; archive preparation happened once within a complete safe codec call,
followed by two necessary hash/output writes, without exporting unchecked writers
or saveable credentials. Count tests confirmed size/encode/stream and archive
preparation validate each node once; all tags, shared budgets, zero output for
invalid trees, and post-overflow validation precedence passed. Related 37
ReleaseSafe and current/old wire tests passed; the frozen before module and 600
alternating comparison rows matched checksum/bytes/shape exactly.

Global sampling omitted RMW for every1, used a bounded 0/1 atomic flip for every2,
and kept other policies and the public layout unchanged; current x86_64 generated
one `lock btc` per every2. Exact-budget tests checked global counts and final
phase, and new configuration-transaction tests locked filter-only preservation
and full-replacement reset. Sampling microbenchmarks passed all budgets before/
final 105 times each, but variance kept stable performance qualification
inconclusive.

The main benchmark supported Memory/mmap shared and SPSC, schema, and durable
file, reporting queue/mapped bytes and recovery capability separately. Five new
bounded executable checks and CSV/failure reports passed; ten captures per
storage confirmed 200,000 written with pending/drop 0 and strictly verified
resource budgets. Standalone sampling cost was not equated with complete log
throughput, and dual storage was not ranked as an equivalent-semantics
optimization.

Ordinary async `memory_queue` and mmap `journal` both supported shared/SPSC,
schema pre-registration, hot configuration, sampling, redaction, and the same
acknowledgement API. Seven external tests covered the no-file-I/O trap, full
queue/shutdown, source deep copy, failed durable reclamation preserving state, and
non-durable policy replacement not taking over the lease. Real SIGKILL confirmed
Memory lost pending records while mmap recovered three; prior written output
survived in both. Dual-mode performance captures confirmed 100,000 written/pending
0/allocation 0 each; different reliability meant they were not ranked as
equivalent optimizations.

The default empty-redaction path removed about 40 KiB of scratch, with non-empty
rules handled in a separate stack function; slot CRC used kron's own IEEE
implementation, optional PCLMUL folding on native x86_64, and portable
slice-by-16 elsewhere, preserving checksums and all format arguments. Module
oracles, independent slot goldens, 416 Vort interoperability groups, and three
redaction-path tests passed.

Complete configuration source transactions and bounded JSON files were
integrated. Seven external transaction tests covered priority, joint policy
publication, filter-only not consuming a route slot or resetting sampling,
failure lease responsibility, SPSC channel reuse, nested guards, and real files.
Two deterministic publication-interleaving tests and a warmed SPSC shared-RMW
counting test were added. Runtime filters became opaque handles, and negative
compilation confirmed public typed APIs could not bypass the unified writer.

After network removal, the remaining formats were text/json/logfmt/binary with
unchanged format numbers. Trace/span was for local event correlation only. TSC
qualification tests distinguished wall and monotonic clocks and verified that
noise-induced calibration failure kept the clock unqualified and fell back to
native.

| Scope | Required evidence | Status at this snapshot |
| --- | --- | --- |
| Build and public module | Zig 0.16 Debug/ReleaseSafe/ReleaseFast, example imports | Debug/ReleaseSafe comprehensive verification passed; ReleaseFast comprehensive gate passed; final close-release correction targeted ReleaseFast verification passed |
| Zig package consumption | Independent `b.dependency` import, source-distribution completeness, thread configuration propagation | ReleaseSafe five modes, single-threaded consumption, and local-fetch source package passed; Windows independent app PE linked; device execution missing |
| Typed fields/encoder | Field boundaries, UTF-8, JSON parsing, secret, format validation | Implemented and passing module/negative-compilation tests |
| Synchronous pipeline/context | Multiple routes, borrow/deep copy, error feedback, no allocation | Implemented and passing Runtime/allocator tests |
| Dynamic configuration | Scope boundaries, concurrent reload, environment priority, old-event decisions | Complete typed sources, bounded JSON file transaction, generation-bound filter-only reload, old admission guard, and SPSC cache without shared RMW implemented and targeted-tested |
| mmap journal | File-backed storage, commit/wrap/checksum, reservation-gap recovery | Implemented; v1/v2 fixed slots, CRC, generation, recovery watermark, and schema synchronized publication tested |
| Process crash recovery | Real SIGKILL, independent cross-process read, duplicate identity | Reserved/committed/gap real kill gates passed |
| Async lifecycle | block/drop, flush/barrier, shutdown races, failing sink | Shared/per-channel gate, flush cut, close publication, and final wakeup tested; deadline formal ReleaseSafe gate passed 11/11 |
| Durable protocol | Output/checkpoint ordering, capability errors, system-fault tests | fsync/dual checkpoint tested; real child-QEMU force-kill ACK1/3 recovered with original image unchanged; physical power loss/random large-scale qualification missing |
| Low latency/SPSC | attach/detach, generation, independent queues, warmup | Owner-only configuration cache and per-channel generation pins integrated; callback TLS lookup/release, detach, and old-generation retention tested |
| io_uring | Capability probe, batched writes, CQE/short-write/in-flight ownership, comparison benchmark | Real local write/fsync/error reclamation passed; comparison evidence retained at that time |
| Rotation and multiple sinks | size/retention/reopen, faults and acknowledgement boundaries | size/time/retention/reopen tested; route snapshots, old record pins, lease hot replacement, and recovery external tests passed; configuration representation opaque |
| Sampling and redaction | fake clock, concurrent counts, secret never enters journal | count/every/token_bucket, redaction, and secret erasure tested |
| std.log/trace | Root-module bridge, lifecycle, TraceContext/Span | Bridge/trace/span used for local correlation; network output removed |
| Tools and archives | kroncat follow/level/where/json/recover, bad tails | Schema/nested/legacy reads, standard zlib compressed archives, and 23 read-only query/follow tests passed; no old-binary dependency |
| Performance | Producer quantiles, drain throughput, saturation/cold cache, resource budgets | Scheduling, real C++ 60/60 comparison, and resource benchmarks completed; prepared schema 64/64 measured; old init timeout evidence retained; further optimization continued |
| Platforms | Windows/Linux/macOS/Android/iOS file, mapping, thread, clock paths and capability boundaries | Linux/Windows/Darwin mapping backends implemented; nine-target ReleaseSafe public-path objects compiled; Linux executed; other device runs pending |
| Single-threaded sync | No background thread, real file output, filter/redaction, flush/shutdown, capability errors | Independent single-threaded executable passed Debug/ReleaseSafe; Linux task count 1; no post-initialization allocation; ordinary durable file flush works; timed/async return explicit capability errors |
| Local reuse | Available APIs, format compatibility, dependencies, actual evidence | Vort 416-group CRC interoperability and ZKV 3,120+8 checkpoint scenarios passed ReleaseSafe; slot CRC uses kron's IEEE implementation, optional PCLMUL on native x86_64, portable slice-by-16 elsewhere; no Vort dependency |

## Remaining acceptance items for the complete goal

The gates above prove implemented capability but do not replace the missing
scopes below.

| Requirement | Existing evidence at this snapshot | Still missing |
| --- | --- | --- |
| Reliability boundaries | Fixed-boundary and random runtime SIGKILL, child-QEMU shutdown, dual checkpoint, fault sink | Larger random system-shutdown campaigns, different filesystems/devices, physical power-loss qualification |
| Low-latency performance | Isolated clock microbenchmarks, prepared 64 rows, C++ 60 trials | TSC hardware/calibration/cross-core qualification verified; still needed: isolated/fixed-affinity stable regression thresholds and business-workload coverage |
| Dynamic policy | Scope/level cache, route/redaction/sampler resource snapshot hot replacement, old-event retention; eight-seed byte-regex differential and fixed mutation campaign | Field predicates and bounded NFA regex, complete source transactions, and bounded JSON files implemented; still needed: sustained sanitizer fuzz, business-regex performance qualification, non-default sampling hotspot optimization |
| Structured extensions | Explicit group/array, 8-level/256-node budget, recursive redaction, nullable/source/trace; restricted object adapter five external tests and nine negative compilations | Broader nested fault and performance qualification |
| Files and archives | size/time rotation, retention/reopen, self-contained and standard DEFLATE archives | More complete persistent-format upgrade matrix, random/more-filesystem fault gates |
| Ecosystem and platforms | std.log, JSON, Windows/aarch64 compilation, real single-threaded synchronous file logging | Windows/macOS/Android/iOS actual execution and journal qualification |

### Priority of current gaps

| Priority | Gap | Evidence and next step at this snapshot |
| --- | --- | --- |
| 1 | Stable complete-workflow performance advantage | The latest 200-trial Foundation spdlog/Rust same-round comparison was entirely inconclusive; only some Memory/Mmap medians led. Establish a quiet-host baseline including flush/shutdown and check CPU/resources and same-semantics cross-library results |
| 1 | Tail latency and application impact under overload | Memory SPSC P4 long-workflow p99.9 remained about 340 µs, and prepared P1 latest long-sampled p99.9 was negative. Cover burst/sustained full queues, slow sinks, more producers; measure blocking/backlog age and compare CPU/cache/scheduling contention with a no-logging baseline |
| 1 | Mmap startup/warmup and resource cost | An earlier same-round SPSC Mmap P4 initialization had a median around 1.25 s; per-producer fixed-slot queues add retention. Reduce cold publication/channel preparation cost and report budgets/lifecycle for real payload distributions while preserving publication/recovery protocols |
| 2 | Performance workload coverage and release regression threshold | Design requires 0/5/10 fields, short/long strings, 1/4/16 producers, warm/cold, frequent attach/detach, reload/rolling, and independent durable throughput/latency. Current complete comparisons mainly use five numeric fields at P1/P4; add business and durable baselines and form a low-noise regression gate |
| 2 | Broader faults and sustained fuzz | Real SIGKILL, child-QEMU, bounded mutation, and coverage-guided tests exist; still needed: multi-filesystem/device system shutdown/power-loss boundaries, longer seeds and sanitizer qualification, nested/rolling/format-upgrade combined faults |
| 2 | Non-Linux platform execution | Windows/macOS/Android/iOS implementations and object/partial-link evidence exist, but actual device logging, lifecycle, recovery, and usable-durability reports are missing; Linux execution is not a substitute |

The API already identifies optional enhancements; future acceptance should state
the source, run result, or explicit platform capability boundary for each item.
This round followed the user's updated single-machine scope; larger hardware
faults and cross-platform qualification remained on the measured-report path.

## Existing execution evidence at this snapshot

- `zig build verify -Doptimize=ReleaseSafe -j2 --summary all` passed 189 tests at
  one development stage (160 library, 11 Runtime integration, 10 query, 8
  benchmark helpers) and executed six compile-fail fixtures and three real
  SIGKILL phases. ReleaseFast later passed 194 tests; final close-release ordering
  and static clock entry corrections passed 10/10 targeted ReleaseFast tests.
  Later source changes must rerun the relevant gates; this is not a guarantee for
  a future HEAD.
- `tests/crash_recovery.py` used a new `kroncat` process to verify that
  uncommitted records are not output, committed source-buffer overwrite does not
  affect the event, complete commits after a reservation gap recover, and two
  inspections do not modify the journal.
- `bench-dispatch` separated clock indirect-call cost from journal/encoder/I/O;
  `std_io`/`native`/`none` were explicit different providers, and native or
  timestamp-removal results were not presented as equivalent-semantics gains.
- `zig build test-deadline -Doptimize=ReleaseSafe -j1 --summary all` passed 11/11
  external tests; three independent `src/core/control.zig` ReleaseSafe tests
  passed. The three bounded mutation/arbitrary-input/format corpora in `test-fuzz`
  passed Debug but were not equivalent to long-running fuzz qualification.
- `tests/power_loss/evidence/2026-10-31/` preserved two real QEMU shutdown
  file/journal confirmation reports. The host was not rebooted, power-cycled, or
  given a mounted test disk; verification booted a temporary overlay.
- Later `verify -Doptimize=ReleaseSafe -j2` passed 280 tests, all five SIGKILL
  phases, and six compile-fail fixtures, covering deadline, v2 schema, Reader,
  legacy codec, and prepared binding mislabeling protection. Rebuilt v3/v2 test
  writers again recovered after QEMU ACK3 shutdown.
- Current `verify -Doptimize=ReleaseFast -j2` passed 280/280; a redaction test
  was corrected to parse `attributes.token` and check the optional actual value
  instead of searching the whole JSON for a secret number. Windows public module
  ReleaseSafe compilation passed.
- Later `verify -Doptimize=ReleaseSafe -j2` passed 358/358 tests (280 library, 9
  configuration, 10 compression, 23 query), six real SIGKILL phases, and the
  original negative compilation. Opaque configuration representation and
  concurrent SPSC replacement targeted Debug/ReleaseFast tests passed 10/10, and
  new negative compilation confirmed public typed APIs could not directly modify
  a Snapshot.
- Current `verify -Doptimize=ReleaseFast -j2` passed 359/359, seven compile-fail
  fixtures, six SIGKILL phases, and four example compilations;
  `run-hot-configuration` ReleaseSafe actually ran and `kroncat` decoded the
  compressed archive. The final SPSC concurrent hot-replacement test covered
  2,000 accepted==written. The complete ReleaseSafe count of 358 predates that
  test; its 10 configuration-targeted ReleaseFast gates and the full current
  ReleaseFast run covered it.

## Continuing requirements

Deadline, child-VM fault injection, schema pre-registration, nested fields,
resource hot replacement, standard compressed archives, and real C++ comparison
were implemented with gates at this snapshot; TSC qualification, field
predicates/NFA, configuration-cache hotspot optimization, and multi-seed
arbitrary-byte regex differential/bounded mutation were implemented. Larger random
fault qualification, a stable regression baseline, sustained sanitizer fuzz, and
more platform execution still needed work.

## Limits of the performance verification at this snapshot

The latest complete bounded benchmark verification timed out during initialization
of the eleventh SPSC sleep configuration; only the main thread was present,
waiting on a kernel file page, with no producer/worker started. That incomplete
verification was not recorded as a pass, and the cause was not asserted to be a
logging deadlock or `std.Io` scheduling cost. Final code-level admission wakeup
and close publication each had targeted tests; initialization I/O tail latency
still needed verification.

## Configuration cache and fast-clock evidence

The ReleaseSafe comprehensive gate passed 388/388; predicate/cache external tests
then passed 5/5; channel pins/cache module Debug/Safe/Fast 27 tests, three real TSC
qualification tests, and wrong-platform compilation passed. A by-reference change
removed the 0x5840-byte `routeMaskIn` memcpy; a single P4 admission measured shared
484 ns/attached 157 ns, with complete JSON throughput 587K/617K. TSC qualified all
100,000 reads with zero fallback, but the current safe implementation at 34.52
ns/call was slower than NativeClock at 18.35 ns, so no TSC performance gain was
claimed.

## Additional qualification in this round

Four independent shutdown boundaries ACK17/31/8/3 in the bounded QEMU campaign all
recovered; 17 and 31 covered 16-slot wrap. The regex differential gate completed
4,096 exact comparisons with Python `re.search`, passing Debug/ReleaseSafe, and a
deliberately wrong-expect negative driver confirmed non-zero failure. TSC's TLS
calibration cache measured 22.88 ns/call versus Native 15.33 ns while preserving
qualification and generation/instance-cookie checks; no TSC speed advantage was
claimed.

An earlier `verify -Doptimize=ReleaseFast -j2` passed 398/398 (309 library, 6
predicate/cache external, 3 real TSC qualification, and the remaining integration/
tool/benchmark tests), six SIGKILL phases, seven compile-fail fixtures, 4,096
regex differentials, and six example compilations. Configuration responsibility
was split into `runtime_configuration.zig`, and owner-instance clock interfaces
plus cross-Runtime thread-local resource lookup/public release qualification were
verified.
