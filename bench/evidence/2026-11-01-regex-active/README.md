# Configuration-time regex closures and active byte states

Baseline: `2106543` (the completed byte-regex boundary repair). The frozen
production trees are `src-before.tar.gz` and `src-after.tar.gz`; only
`src/pipeline/regex.zig` changes. `source-manifest.json` records source hashes
and the benchmark build command. Executable hashes are in each comparison
manifest; generated executable copies are ignored by Git.

The matcher compiles four BOL/EOL contexts into consuming/ACCEPT-state
closures. State owns two BOL=false closures; Regex owns its two initial
BOL=true closures. Runtime merges two u64 masks and enumerates consuming
states with ctz. Search still starts at every position; all nullable and
anchor loops are resolved within fixed state budgets, and `$` means the
absolute input end. State indexes remain absolute in a Predicate's shared
array, so configurations containing multiple regexes cannot cross graphs.

`regex-before.zig` and `regex-after.zig` are the actual frozen matcher files.
Two investigated intermediate algorithms are preserved as
`regex-active-list.zig` / `comparison/` and `regex-epsilon-only.zig` /
`closure-comparison/`. They regressed overlapping alternation by about 44%
and 23% in their respective noisy median comparisons. These were not
integrated. Final `context-comparison/` resolves that negative median and
retains all final slow samples.

## Workload and output qualification

`bench/regex.zig` tests eight Pattern/Predicate workloads (HTTP paths, severity
messages, long literal search, nullable loops, overlapping alternation,
128-state limit, dense character classes, NUL/high bytes) and two full
synchronous JSON cases. Long cases reduce attempts while retaining all four
inputs. Each case contains two matches and two misses. Isolated cases report
batch-average match cost. Full sync includes captured fields, validation,
predicate, encoder, complete output hash/copy and written flush, with failed
allocator admission after initialization. Final JSON fields are parsed.

Five alternating before/after pairs, each with five repetitions, run pinned
to CPU 0. All **900 rows** agree on input bytes, attempts, matches, written,
output bytes, JSON hashes and measurement environment. The comparison
driver's negative checks reject missing/duplicate rows, count drift, bad time,
output drift and runtime allocation. Final cases all exceed the 10% noise
budget; no stable end-to-end or cross-library speed claim is made. Median
changes and exact retained samples are in `context-comparison/summary.json`.
This probe covers synchronous JSON counters and matcher batches, not async
queue/file/durable throughput or single-call tail latency.

`resources.log` and `resources.zig` measure fixed sizes and 1000 compile
attempts. Native x86_64 Pattern grows **4624 -> 9264 bytes**; Predicate grows
**17952 -> 25632 bytes**, including all 64 fixed rule slots. Input/config
string budgets are unchanged. The compile probe reports higher configuration
cost (roughly 0.9 -> 2.0 us for API paths and 1.1 -> 3.2 us for a 127-literal
pattern), rather than hiding cold-path work in isolated hot-path results.

`pmu/` captures five additional identical whole-probe pairs, including
initialization/compilation, all isolated cases, both full sync cases and JSON
reports. User PMU excludes kernel work. The first capture in `pmu-first/`
failed because the driver attempted to parse a hybrid CPU's uncounted atom
PMU row; it is retained as a driver failure. The corrected driver skips
non-numeric rows and requires one real counter for each requested event.
The whole probe's instructions decrease 81.34% with relative spread below
0.00005% on both sides; cycles still exceed the noise budget. Whole-probe
counters cannot be used as full asynchronous/file workflow proof.

## Semantic gates and coverage guided fuzz

`differential/` repeats all eight independent Python bytes-oracle seeds with
the final ReleaseFast driver: **161872 exact outcomes**, including 161504
matching outcomes, 360 exact compile rejections and 8 over-limit errors;
**64 negative driver checks** pass. Original corpus files remain in the
boundary-repair evidence as well. `module-debug.log` and `module-fast.log`
cover all byte pairs, exact state/depth budgets and closure/assertion loops.

`tests/regex_equivalence.zig` has an independently structured dense
fixed-point graph interpreter: 8192 mutations, shared graph offsets,
64-bit word boundaries, exactly 128 total shared states and absolute anchors.
Its fuzz test mixes known complex graphs, arbitrary compile/input bytes and
arbitrary predicate specs. The final temporary source copy completed
**1004626 ReleaseSafe coverage-guided runs** (`fuzz-context.log`); the public
build entry completed **1006557 runs** (`fuzz-main.log`). Counts include
discovery runs; each fuzzer report records unique runs and coverage. Those
two runs predate the added dedicated shared-word-boundary unit test; the
final gates check that test separately.

ReleaseSafe runtime checks and Zig fuzz coverage instrumentation are used.
These are bounded native Linux campaigns, not an AddressSanitizer,
ThreadSanitizer, continuous fuzz or other-device qualification. Broader
performance and platform requirements remain in the main acceptance list.

Final integrated `verify-safe.log` passes **89/89 build steps and 520/520
tests**. Debug and ReleaseFast directed public gates each pass **13/13 tests**,
including the later exact-budget shared-word test. The standalone module
passes **6/6 tests** in all three optimization modes. The initial combined
platform/package command completes all nine platform objects but fails the
package fetch: staging a live bench tree copied about 3.8 GB of ignored
workloads. The package stage now excludes generated benchmark artifacts and
executables while keeping source/reports; `distribution.json` and
`distribution.log` verify the fetched package's five modes. The original
fetch timeout remains in `platform-package.log`.

```sh
zig build test-regex-equivalence test-regex-differential test-regex-fuzz \
  test-predicates test-regex-bench -Doptimize=ReleaseSafe -j1 --summary all
zig build test-regex-equivalence -Doptimize=ReleaseSafe --fuzz=1M -j1
zig build bench-regex -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5
zig build verify-local -Doptimize=ReleaseSafe -j2 --summary all
zig build check-platforms -j1 --summary all
```
