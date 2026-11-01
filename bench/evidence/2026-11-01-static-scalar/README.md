# Type-directed scalar capture and bounded wire lengths

Baseline: Git commit e5f189e. before-source.tar.gz freezes the baseline;
after-source.tar.gz freezes the combined candidate, with exact source/binary
SHA256 in both provenance files and source-manifest.json. Isolated
scalar-only-source.tar.gz and size-only-source.tar.gz preserve the variants
used to distinguish changes. Only field.zig, wire_size.zig and codec.zig
production-tree files change; codec's change is a boundary regression test.

## Capture semantics

Named fields known at compile time to contain only scalar captures count one
node without dispatching through dynamic ValueValidator.value. fromAny still
checks their exact supported types. Integers, floats, string/bytes slices,
optional scalars, tags, errors, durations/timestamps and erased secret values
keep the same captured representation. Unknown/dynamic Value, Array, Group
and optional containers still use the complete validator. Existing prefixes
retain duplicate and nested validation; dynamic tuple/slice inputs retain
all prior validation. A mixed tree uses one combined 256-node budget, and
errors leave the visible count unchanged.

Capture validation is not reused across a clock callback. Public Runtime
submission measures/validates the final borrowed tree again, before predicate
and reservation. The new public test makes a borrowed array cyclic during
the injected wall clock: shared/SPSC emit returns CyclicValue without reserving
or accepting, then a repaired tree emits exact JSON successfully. No proof
hint, unchecked entry point or new public API is introduced.

## Size semantics

Wire-size total changes from u128 to u64, capping each individual term at
u32_max+1. A supported wire payload is at most u32_max, so any capped term
still ensures TooLarge at the final result. At most 256 nodes/keys and five
metadata strings bound the sum below 2^42. Complete validation precedes result,
so later cyclic/duplicate errors still take priority over an earlier huge
length. Runtime level/predicate ordering and schema shape/level ordering are
unchanged. There is no reading of a logical oversized slice by the size-only
path and no change to persistent tags, payload bytes, CRC or schema format.

The arithmetic test compares capped results with u128 exact sums in 8192
mixed sequences, including maxInt(usize), exact u32 limits and valid sums.
The codec regression exercises logical huge strings plus late cyclic and
duplicate fields/arguments, proving zero output on failure. See the owning
wire-size experiment in ../2026-11-01-wire-size/ for isolated probe results.

## Complete process evidence

Combined and scalar-only each run 20 full real-file PMU trials: SPSC Memory
P4 and shared Memory P1, five alternating pairs, 300000 measured + 1000 warmup
records, full JSON, system wall clock, 256 slots/512-byte payloads, 64KiB file
buffer and CPU0/2/4/6/8/10 affinity. Every physical record is independently
verified after written flush, shutdown and cleanup. Each variant verifies
6,020,000 JSON records. User PMU counts the whole application process,
including producer/worker/startup/close, excluding kernel work.

| Variant | SPSC P4 user instructions | Shared P1 user instructions |
| --- | ---: | ---: |
| static scalar only | -2.68% | -2.97% |
| static scalar plus bounded sizes | -3.00% | -3.32% |

These instruction counts pass the 10% spread threshold. Combined counts are
2,889,075,699 -> 2,802,344,198 for SPSC P4 and
2,700,784,464 -> 2,611,099,187 for shared P1. Cycles/throughput for all PMU
variants remain inconclusive; instruction reduction is CPU work evidence,
not a stable speedup or cross-library ranking. The isolated public encoding
probe retains exact inline/schema/binary output hashes across 900 report
rows; it reduces instructions 2.89% but increases cycles 2.45%, with all
per-case times inconclusive. That probe is a different scope.

## Full workflow and tail limits

100 paired full-file trials cover shared Memory P1/P4, SPSC Memory P4,
SPSC Mmap P4 and prepared SPSC Mmap P4, sampled and batch in separate
processes, five pairs each. Every trial verifies 100000 measured plus 1000
warmup records: **10,100,000 physical records**, all accepted=written,
drop/pending=0. Source and binary hashes are guarded before/after each trial.
Throughput includes final written flush, shutdown and object/file cleanup;
init/preparation remain separate lifecycle metrics. No durable media flush.

| Batch configuration | Before records/s | After records/s | Median change |
| --- | ---: | ---: | ---: |
| Shared Memory P1 | 1944377 | 1867754 | -3.94% |
| Shared Memory P4 | 1989623 | 1996412 | +0.34% |
| SPSC Memory P4 | 1885556 | 1830646 | -2.91% |
| SPSC Mmap P4 | 2011027 | 1961560 | -2.46% |
| SPSC Mmap P4 prepared | 1668191 | 1649907 | -1.10% |

All groups are inconclusive with overlapping bootstrap intervals; every
slow sample remains. SPSC Memory P4 sampled p50 median improves 482->277ns,
but p99 worsens 987->9729ns (before spread 7.72x, after 0.254x). SPSC mmap
p99 also worsens 997->8307ns and remains inconclusive. No blanket latency
improvement is claimed. The longer sampled capture separately evaluates
that observed tail concern, and its limits are reported alongside this data.
This library still needs stable throughput/tail and Foundation/spdlog
same-round qualification; these local CPU percentages are not added to an
archived cross-library rank.

The separate long sampled capture completes another **20 trials and
6,020,000 verified physical records**, without concurrent local gate builds.
SPSC Memory P4 p50 median falls 416->281ns, while p99 rises 1051->10143ns
and p99.9 rises 360195->420294ns. Before p99 spread is 5.83x and after is
1.20x; after throughput has a retained slow sample at 1.327M records/s.
Shared P1 p99 median falls 918->831ns, but p99.9 rises 9832->15249ns.
All tail/throughput groups remain inconclusive, so the repeated SPSC
negative median is a material limit, not discarded as a favorable noise
interpretation. The retained optimization demonstrates fewer whole-process
instructions; it does not qualify improved producer tail or completion time.

Final native scalar/size tests run in Debug/ReleaseSafe/ReleaseFast, public
capture/adapter/predicate/redaction gates and the full composite gate check
actual lifecycle, journal, formats and failures. Exact gate counts and source
identity are in qualification.json once the full gate finishes. Platform
object compilation is separately recorded; it does not prove device execution.

Final ReleaseSafe `verify-safe.log` passes **89/89 steps, 527/527 tests**,
including real SIGKILL recovery, independent package consumption, fused and
nested format paths, logical oversize/tree error priority, ownership and
no-allocation checks. `platforms.log` generates all **9** actual ReleaseSafe
target objects (10/10 build steps), including non-x86 and generic x86 paths.
The final directed ReleaseFast capture/predicate/encoding gates pass 15/15
tests. `qualification.json` binds these gates to source hashes and records
the outstanding throughput, tail and cross-library qualification limits.
