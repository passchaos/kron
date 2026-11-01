# Consumer profile and fused schema reference candidate

Baseline commit `366adc3` includes bounded coalesced delivery windows. All
measurements use the public `bench/cpp_reference/kron_reference.zig` full-file
workflow, with the owning independent JSON oracle in `run.py`. Source archives
and per-file SHA256 bind the before/candidate binaries to actual implementation.

## Current-path profile

Six user-cycle profiles complete **6,006,000 independently checked physical
JSON records**: Memory/Mmap × shared/SPSC inline P4, plus SPSC prepared-schema
Memory/Mmap P4. Each has1M measured+1k warmup records, complete metadata/five
numeric attributes, system wall clock,256 slots/512-byte payload,64KiB file
buffer and default4 consumer quanta, with portable selected explicitly.
Affinity is CPU0/2/4/6/8/10. The host is loaded; perf sampling includes setup,
preparation and cleanup and excludes kernel work. Relative sampled cycle shares
do not establish wall-time improvement or causation for cross-library results.

The inline SPSC Memory profile attributes about52% of core user cycles to the
consumer, including34% to fused wire rendering. The prepared SPSC Memory
profile still includes `decodeRecord` (about11% including children) and
`memcpyFast` (about15% self), which also includes producer copies. Shared
Memory inline instead has about25% self attributed to Runtime.begin. These
are candidates for measurement, not permission to weaken validation or proof
that a particular lock/cache line causes the cost. Raw data, symbol reports,
begin disassembly and per-file record/hash checks remain alongside the scripts.

The initial profile requested2M records, exceeding the existing public harness
limit of1M. It exited `InvalidOptions` before running the workload. Its logs
and three setup samples are retained with `initial-invalid-options-` prefixes
and excluded from completed profile evidence. The subsequent six profiles
honor the existing input limit.

## Candidate and semantics

For a checked schema reference in a window with at least64 already-ready
records, single JSON/text/logfmt route, nondeferred
message and zero format arguments, the consumer uses the validated definition
directly for scope/source/static keys and reads values while formatting into
its existing scratch. It avoids materializing the top-level Event fields and
the subsequent attribute traversal. Values retain tag/type-mask, nested
descriptor/node/depth and complete-length checks. Top-level key uniqueness
continues to come from the checked owning schema registry. No persisted
pointers, format change, smaller journal or new heap allocation is introduced.

The common checked reference header is shared with materialized resolve.
Unsupported template/multi-route/binary shapes use the materialized path, with
one canonical definition lookup reused within that record. Route-lookup errors
and invalid masks still perform reference decode first on their cold rejection
path, retaining the original decode-before-route error priority. Sink calls
occur only after successful complete scratch rendering. Output barriers,
second checked record reclaim, written/pin accounting and recovery are unchanged.

Differential tests compare all scalar tags, integer extremes, nonfinite floats,
invalid UTF-8/control bytes, source/trace, dynamic/static messages, nested
attributes, readable timestamps and historical v2 output across three formats.
4096 seeded mutations, all truncated prefixes, appended bytes and small scratch
capacities compare the exact error/output with materialized resolve; guarded
scratch checks boundaries. A real runtime test exercises48 cases across
Memory/Mmap×shared/SPSC and header mismatch/late type mismatch/type+invalid-route
damage with a fresh valid slot CRC,1/64 pending records and16/512-byte output
scratch. All produce zero sink records, written0, retain their pending count
and the expected configuration pins. Templates retain their
existing successful formatting and unused-argument rejection via fallback.

Initial test compilation/setup failures are retained, including wrong time
option declarations and a recovery callback signature mismatch corrected before
the final candidate freeze. `reference-runtime-callback-safe.log` passes26
related tests including the existing coalesced failure/reclaim cases.

## Paired measurement

`measure.py --pmu` captures five paired complete-file user-counter runs for
prepared SPSC Memory/Mmap, prepared shared Memory and inline SPSC Memory as a
control. `measure.py` captures prepared shared/SPSC Memory/Mmap P1/P4 plus
inline shared/SPSC Memory/Mmap P4, in both batch and sampled phases, five pairs.
Counters include full process setup and exclude kernel work; wall-time reports
separate initialization/preparation from the written flush/shutdown/cleanup end.
Every row checks the actual portable backend and unchanged budgets. Completed
rows are saved immediately, and failed workload directories remain for review.

The initial full-schema fusion completed240 whole-file trials and40 PMU
trials:36,280,000 physical records. Schema user instructions fall about1.76%
(SPSC Memory/Mmap) and1.85% (shared Memory), while inline control instructions
increase0.26%. Several P4 groups improve, but shared Memory P1 throughput has
a negative median. Two10-trial1M-record captures recheck that result; the first
one's initial pair overlaps the tail of a directed test and is marked as such.
The clean capture still has a negative median1.71% with overlapping intervals.
A by-reference header candidate passes correctness but its clean long P1
median is4.62% lower, so that experiment is rejected and its sources retained.

The final candidate selects materialized resolve on shorter than64-record
windows and fused output on backlog; no wait or new service budget is added.
A10-trial1M-record check has a negative P1 median0.65%, with bootstrap intervals
overlapping. This is not proof of universal P1 neutrality or improvement.
Short-output failure performs materialized validation on the cold error path
so later schema damage retains its original error priority. All versions and
negative results remain separate; final bounded capture is identified by its
own provenance and distribution files.

All slow observations, percentile/CV/spread/bootstrap distributions and source
guards are retained. Final decisions and gate identities are recorded in
qualification.json after capture and related gates finish. This evidence does
not provide a fresh Foundation/spdlog or portable/io_uring ranking.

One final bounded workflow capture stopped after187 saved successful rows
(18,887,000 physical records) because two source comments were edited during
the watched-source interval. The source-hash guard correctly rejected the
changed state. The frozen source was restored, raw interrupted data and logs
are preserved separately, and a fresh complete240-trial capture was started.
The interrupted rows do not supply a complete qualification.
The replay reused the same per-trial log filenames; saved original JSON rows
retain their complete metrics/commands/hashes, while intermediate stdout log
copies were overwritten. The unsaved final workload is still retained in its
temporary directory and parsed as101000 complete JSON lines; `interruption.json`
records its path/hash and this preservation limit without treating it as a
timed successful row.

## Final bounded full-file workflow

The fresh complete240-trial bounded capture independently checks24,240,000
physical records. The interrupted187 rows are excluded. Final batch medians
and noise qualification follow; these are same-round before/after comparisons.

| Mode/storage/producers | Before M/s | After M/s | Change | Qualification |
| --- | ---: | ---: | ---: | --- |
|shared memory P1 schema|1.698|1.745|+2.75%|inconclusive|
|shared memory P4 schema|1.921|2.043|+6.35%|repeatable; intervals do not overlap|
|shared mmap P1 schema|1.813|1.728|-4.72%|inconclusive|
|shared mmap P4 schema|1.906|2.045|+7.31%|inconclusive|
|SPSC memory P1 schema|1.910|1.971|+3.23%|inconclusive|
|SPSC memory P4 schema|2.078|2.245|+8.03%|repeatable; intervals do not overlap|
|SPSC mmap P1 schema|1.885|1.906|+1.09%|repeatable; intervals overlap|
|SPSC mmap P4 schema|1.995|2.211|+10.83%|inconclusive|
|shared memory P4 inline control|2.218|2.288|+3.16%|repeatable; intervals overlap|
|shared mmap P4 inline control|2.253|2.285|+1.40%|inconclusive|
|SPSC memory P4 inline control|2.389|2.423|+1.41%|repeatable; intervals overlap|
|SPSC mmap P4 inline control|2.358|2.438|+3.37%|inconclusive|

CV and relative spread below10% define local repeatability; interval overlap
limits confidence in the size and direction of a median difference. In particular
shared Mmap P1 has a negative4.72% short-workflow median and is rechecked in a
separate1M-record capture. Earlier candidates do not qualify the final source.

Shared Memory schema P4 producer p99 median28438→24894ns, but p99.9
41710→46586ns; both are inconclusive. SPSC Memory schema P4 p99.9
374003→330994ns meets the local noise budget, while p99 is inconclusive.
Mmap tails remain inconclusive. A throughput improvement is not a universal
tail improvement, and initialization/lifecycle metrics retain all slow samples.

Native `drainJournal` explicit stack allocation is37800→40712 bytes (+2912)
for the final candidate. This disassembly measurement excludes register pushes,
callees and recursive/transitive stack use. No new heap or journal/file budgets
are introduced. All stage-specific frame measurements remain in resources.json.


## Final PMU and negative-median review

The final40-trial user PMU capture independently verifies12,040,000 physical
records. SPSC schema Memory/Mmap instructions decrease1.804%/1.802%, shared
Memory schema decreases1.906%; all CV/spread pass and intervals do not overlap.
The inline SPSC control increases0.171% instructions, also repeatable.
Cycles remain workload/host-dependent; CPU reductions are not total latency
or cross-library rankings.

The final ordinary1M-record shared Mmap P1 follow-up completes10 trials
and10,010,000 verified physical records. Median throughput is1.390% lower
with both sides within the local repeatability budget, but bootstrap intervals
overlap. Together with the short-workflow negative4.72% and the final shared
Memory P1 long negative0.65%, these are retained limitations. The candidate
has qualified Memory P4 gains, not demonstrated universal P1/Mmap neutrality.
No test/build from this task overlaps the final complete workflow, final PMU,
bounded long P1 or Mmap long P1 capture.

## Final gates

`zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all` completes
93/93 build steps and545/545 Zig tests, including owning decoder/fuzz matrices,
48 runtime fault cases, random process-crash recovery, independent five-mode,
single-threaded and source-distribution packages, Linux host qualification,
negative compilation and tools. The TSC calibration is unstable in this loaded
host window and its owning qualification deliberately uses the native fallback;
that passing fallback is not evidence of a faster TSC clock.

`zig build check-platforms -Doptimize=ReleaseSafe -j2 --summary all` completes
10/10 steps for nine actual object targets. Cross-compilation does not establish
non-Linux device execution. Final directed Debug/Safe/Fast checks each pass26
tests; their frozen source matches the final binary and archive identities.
Logs, whole-file measurement/distribution audits and qualifications remain in
`qualification.json`. No required output, second CRC or durable protocol was
removed, and no new power-loss/platform-device capability is claimed.

Per-trial stdout logs and PMU CSV are archived under `trials/<capture>/`;
the original commands retain their capture-time output paths. The reproduction
script now writes into the matching subdirectory. Root result files remain
append-only complete/incomplete capture records, with all original hashes.
