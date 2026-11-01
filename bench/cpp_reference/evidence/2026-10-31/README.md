# C++ and kron file pilot, 2026-10-31

Three repetitions, two producer counts (1/4), and sampled/batch phases for each
strategy produced **60 successful trials**. Every trial verified all 10,000
measured and 1,000 warmup records independently in Python; C++ also performed
exact-payload readback. Total validated records: 660,000. No missing/duplicate/
partial records, drop, or final pending remained.

| Configuration | P1 batch median records/s | P4 batch median records/s | P1 sampled median p50 | P4 sampled median p50 | Process-crash recovery |
| --- | ---: | ---: | ---: | ---: | --- |
| spdlog 1.12, producer JSON format | 1,288,942 | 803,928 | 733 ns | 1,556 ns | No |
| Quill 9.0, producer JSON format | 3,064,276 | 2,703,662 | 310 ns | 231 ns | No |
| Quill 9.0, deferred JSON format | 3,363,298 | 2,861,202 | 42 ns | 42 ns | No |
| kron, shared mmap journal | 592,239 | 619,593 | 872 ns | 1,197 ns | Yes |
| kron, SPSC mmap journals | 657,590 | 637,237 | 897 ns | 947 ns | Yes |

These are **different reliability and output contracts**, with common logical
input and verified final completion. Minimal C++ JSON wrote 1,044,490 measured
bytes per trial; kron wrote roughly three times as many bytes with normal event
metadata. Quill defers fixed-format numeric arguments, while kron captures a
self-contained structured event into a recoverable journal. Queues use different
units/budgets. This table is not a universal logger ranking or a recovery-matched
performance contest.

The i9-13900K host was unreserved and unpinned, with 32 logical CPUs, GCC 13.3,
Zig 0.16 ReleaseFast, and ext4 output. Some completed runs were severe outliers:
spdlog P4 batch minimum 13,693 records/s and kron SPSC P4 batch minimum 53,255
records/s. All such trials remain in the raw results and min/max summary. Large
p99.9 tails and outliers require controlled repeated profiling; they are not
discarded or attributed to a single library mechanism without evidence.

`manifest.json` pins official archives/include hashes, exact compiler commands,
source/binary hashes, machine and filesystem information. `results.jsonl`
preserves each invocation and file hash. `summary.json` includes median/min/max
and p50/p99/p99.9. The original artifact files and binaries remain under
`/tmp/kron-cpp-comparison-20261031-complete`; they are excluded from the repository
and may be removed by temporary-storage cleanup.

`initial-notifier-classification.json` preserves an earlier **harness error**:
Quill blocking INFO notifications were misclassified as delivery failures. This
was fixed against the pinned source; all final P1/P4 trials pass. The separate
`perf-quill-note.md` records available hardware counters and their hybrid-CPU/
initialization scope limitations. `post_capture_validator.json` identifies the
validator used to recheck all artifacts after capture.

Reproduce with:

```sh
python3 bench/cpp_reference/run.py \
  --deps-dir /tmp/kron-cpp-bench-deps --output-dir /tmp/kron-cpp-comparison \
  --libraries spdlog,quill,kron --events 10000 --warmup 1000 \
  --repeats 3 --producers 1,4
```
