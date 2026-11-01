# Direct native decimal output into existing Writer capacity

Baseline: Git commit `20d49be`. `before-source.tar.gz`, `after-source.tar.gz`,
`source-manifest.json`, both provenance files and `implementation.patch`
retain exact sources and binary identities. The unchanged C++ comparison
Zig harness calls the real public logger, captures full system timestamps
and writes complete JSON to actual files. Only encoder/decimal.zig changes.

When at least 21 bytes remain in Writer's current buffer, the native integer
renderer computes its exact digit count and writes backward directly into
those bytes, then publishes only the actual used length. It never drains or
rebases Writer and retains the bounded-stack writeAll path when capacity is
smaller or magnitude exceeds u64. Wide values keep 10^19 chunks; signs,
JSON string precision policy, floats, deferred width/base formatting and
UTF-8 escaping remain identical. A separate noinline native helper keeps the
loop out of recursive value rendering's larger frame. The table of powers
uses 160 read-only bytes. No runtime allocation or buffer budget is added.

## Boundary and error evidence

Final scalar module tests pass 5/5 in Debug/ReleaseSafe/ReleaseFast, including
all 65536 u16 values, native/wide extrema, decimal/binary boundaries,
2048 wide random pairs and 4096 native signed/unsigned random pairs. Existing
prefix bytes and unused buffer sentinels remain intact. A buffered Hashed
Writer exercises 1/20/21/64-byte buffers, physical sink chunks 1/3/7 and every
output failure position, with no callback after failure.

`differential-final-safe.log` compares frozen and final public encoders:
12 complete text/JSON/logfmt records, 16486 fixed-buffer failure prefixes,
and 49494 generic Writer success/failure prefixes are byte identical.
`integration-safe.log` verifies real time/configuration/predicate/file paths.
Final full and platform build gate logs record their exact counts separately.

Final `verify-fast.log` passes **89/89 steps and 522/522 Zig tests**,
including real crash recovery, independent package consumption, no-allocation
paths, configuration/predicate semantics, nested/fused encoders and query
tools. Directed ReleaseSafe public integration passes **30/30 tests**;
independent public encoder differential passes in both Debug/ReleaseSafe.
`platforms.log` generates all nine actual ReleaseSafe target objects;
10/10 steps pass. `qualification.json` binds gate counts to the measured
source hashes and records the remaining performance/device limits.

## Explored candidates

`decimal-estimate.zig` is the first direct inline renderer; its 100 trials
are in estimate-results.jsonl / estimate-comparison.json. Full-file counts
pass, but isolated nested20 median increases about 3.2%. An alternative
128-bit digit-count table (`decimal-table.zig`, probe-table/) also retains
that negative nested median. Neither is the final implementation.

`decimal-helper.zig` uses a separate native function and removes this
negative median in a five-pair CPU0 probe. All probe outputs have identical
full JSON hashes/bytes. Final helper scalar5/nested20/wide5 median costs
fall about 4.27%/1.41%/1.37%, whole-process user instructions about 0.34% and
cycles about 1.78%; all probe relative spreads are below 10%. This includes
input mutation, public encoder validation, full-output Wyhash, startup and
report output; it cannot be translated into file throughput. The first
probe capture overlaps local full-workflow compilation; probe-serial and
later probe-table/helper captures run without this local build overlap.
All original positive/negative medians remain retained.

## Final full-file workflow

100 completed trials, five paired repetitions of shared Memory P1/P4,
SPSC Memory P4, SPSC Mmap P4 and schema/prepared SPSC Mmap P4; each runs
sampled and batch independently. Every trial has 100k measured and 1k
warmup, system wall clock, 256 slots/512-byte payload, 64KiB file buffer and
CPU 0/2/4/6/8/10 affinity. The independent oracle verifies all **10,100,000
physical JSON records**, with accepted=written and pending/drop=0. Output
hashes/IDs/attributes/framing are checked before artifacts are cleaned.
Source and executable hashes are guarded before and after each trial.

Throughput below includes producer, background encode/file delivery, final
written flush, shutdown and object/file cleanup; initialization/preparation
are reported separately under lifecycle. No fsync/durable media flush.

| Batch configuration | Before records/s | After records/s | Median change |
| --- | ---: | ---: | ---: |
| shared Memory P1 | 2185176 | 2269482 | +3.86% |
| shared Memory P4 | 2116585 | 2188632 | +3.40% |
| SPSC Memory P4 | 2110843 | 2196063 | +4.04% |
| SPSC Mmap P4 | 2153389 | 2217884 | +3.00% |
| SPSC Mmap P4 prepared | 1814685 | 1874776 | +3.31% |

Each side meets this round's 10% CV/spread threshold. Only SPSC Memory P4's
trial-bootstrap median intervals do not overlap; the other four do. The
full distributions, initialization costs and sampled p50/p99/p99.9 are in
comparison.json. SPSC tail medians show no broad tail regression; individual
p99 groups remain noisy, shared P1 p50 rises 339 -> 346ns and prepared SPSC
p50 rises 482 -> 487ns. Small medians are not universal latency guarantees.
Current Foundation/spdlog full-workflow comparison uses the earlier frozen
source, so these local before/after percentages are not added to that ranking.

`full-pmu/` records further complete-file paired process counters; each
300k trial independently checks 301k physical JSON records. These include
producer/consumer, written flush, close and cleanup, unlike the encoder-only
probe. Kernel I/O cycles are excluded by the user-PMU scope.

All **20** additional PMU trials verify **6,020,000 physical records**.
SPSC-memory P4 user cycles fall 4.99%, both spreads below 4.4%, while user
instructions increase 1.00%; shared-memory P1 instructions increase 1.04%
and cycles remain inconclusive. This renderer changes instruction mix and
copy cost rather than reducing every full-process instruction count.
SPSC PMU throughput median rises 5.17%, but a retained after sample at
0.414M records/s makes this longer-workflow throughput inconclusive.
Shared P1 median rises 1.47%, with both spreads below the budget. These
longer-process limitations remain alongside the 100-trial results; they
are not discarded or generalized into a stable cross-library ranking.

Reproduction:

```sh
zig test src/encoder/decimal.zig -O ReleaseSafe
zig build verify-local -Doptimize=ReleaseFast -j1 --summary all
zig build check-platforms -j1 --summary all
```

The evidence scripts use frozen/reference executables whose paths and hashes
are recorded; rebuild them from the retained sources before replaying a
capture into a fresh destination. Do not overwrite a completed trial report.
