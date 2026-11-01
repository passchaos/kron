# Current portable/io_uring complete file workflow

Production source matches commit `c4b7f34`. This capture uses the same
ReleaseFast executable for both file backends. The reference harness adds
explicit `--backend=portable|linux_uring|auto` and reports actual selection;
its ordinary default remains portable. The library's FileSink `auto` selects
io_uring if available and falls back only on Unsupported; availability does
not imply the faster backend for a particular workload.

`measured-source.tar.gz` freezes all production source and the exact initial
harness, comparison driver, file oracle and regression statistics used for
capture. `source-manifest.json` and `comparison/manifest.json` record source
and executable hashes. `final-check-sources.tar.gz` separately freezes the
later tests/build gates and factored validation helper. Those later edits
add backend/budget negative checks and do not change the trial data or
production implementation.

## Verified comparison

**160/160 trials** complete, independently checking **16,160,000 physical
JSON records** (16M measured plus 160k warmup). Every trial accepts/writes
100000 measured events, pending/drop0. Each output is parsed after complete
close, validating full metadata, five numeric attributes, unique IDs,
newline framing, physical bytes and content SHA256. Every io_uring report
confirms `backend_requested=backend_selected=linux_uring`; none fell back.
Files are deleted only after their complete verification succeeds, with
hashes and per-trial reports retained in `comparison/results.jsonl`.

Linux x86_64 i9-13900K, kernel6.8, NVMe ext4, Zig0.16 ReleaseFast, fixed
CPU0/2/4/6/8/10. Memory/Mmap, shared async/SPSC, P1/P4 run in independent
batch and sampled processes, five alternating backend repetitions. System
wall clock, full JSON, 256 slots with512-byte payloads,64KiB output buffer,
queue depth4 and consumer budget4 remain fixed. The backend buffer/ring
resource overhead is additional and retained in the frozen implementation.
No rotation, predicates, sampling, compression or strict durable file flush.

Written throughput includes producer, checked consumer/encoding, actual
file writes, final written flush, shutdown and object/file cleanup.
Initialization/preparation are reported separately; sampled producer-call
percentiles are not final record-visible latency. Raw intervals, slow values,
CV/spread and bootstrap results are in `comparison/summary.json`.

## Result

Five batch-process medians, millions of written records/second through close:

| Queue/storage | Producers | Portable | io_uring | Change |
| --- | ---: | ---: | ---: | ---: |
| shared Memory |1|2.122|1.770|-16.6%|
| shared Memory |4|2.127|1.733|-18.5%|
| shared Mmap |1|2.180|1.812|-16.9%|
| shared Mmap |4|2.132|1.752|-17.8%|
| SPSC Memory |1|2.230|1.833|-17.8%|
| SPSC Memory |4|2.124|1.763|-17.0%|
| SPSC Mmap |1|2.217|1.811|-18.3%|
| SPSC Mmap |4|2.164|1.750|-19.1%|

Six of eight groups meet the10% CV/spread threshold on both sides; shared
Memory P1 and SPSC Mmap P4 remain inconclusive under that threshold. Every
paired group's bootstrap median intervals do not overlap. This is a local
complete-file workload result: **io_uring is slower in this measured shape**,
not a proof that it is slower for all file sizes, devices or I/O overlap.
No current Foundation/io_uring cross-library comparison is implied.

Sampled P4 p99 medians in ns: shared Memory16001→23011, shared Mmap
16561→22995, SPSC Memory10145→17382 and SPSC Mmap10311→16905.
All per-metric qualifications and p99.9/initialization remain in the report;
these particular medians cannot replace the full tail distributions.

## I/O window and limits

The runtime currently flushes required output after every checked batch,
before releasing its journal slots. A64-record JSON batch is smaller than
the64KiB file buffer in this workload, so a flush commonly sends one write
batch. The io_uring backend first copies into its stable pool, submits SQEs,
handles CQEs/short-write retries and waits at flush before reclaim. Portable
writes the buffered bytes positionally and completes that barrier directly.
This narrows the overlap window in this test. It is an implementation
explanation to investigate, not an attributed CPU profile proving what
fraction of the difference comes from any individual operation.

An additional traced actual io_uring P4 SPSC Memory process independently
verifies101000 records. The syscall summary and full workflow are retained
in `uring-syscalls.txt`/`uring-trace-verified.json`. Trace timing is not used
as benchmark qualification. The initial smoke independently verifies1100
physical records and also confirms actual io_uring.

## Reproduction and checks

```sh
zig build-exe -O ReleaseFast --dep kron \
  -Mroot=bench/cpp_reference/kron_reference.zig \
  -O ReleaseFast -Mkron=src/root.zig -femit-bin=/tmp/kron-file-reference
python3 bench/cpp_reference/compare_backends.py \
  --binary /tmp/kron-file-reference --output-dir /path/to/fresh-capture \
  --events 100000 --warmup 1000 --repeats 5
zig build test-cpp-reference-report test-integration -Doptimize=ReleaseSafe -j2
```

The report gate rejects incomplete JSON/written counts, actual backend
fallback, changed modes and queue/record/consumer budgets. Three Python
negative-verification tests and the harness option test pass. Directed
ReleaseSafe build passes8/8 steps and14/14 Zig tests (13 public runtime
tests plus one harness test), including the new Memory/Mmap failure wake
regression. Debug/Fast also check that retained runtime failure scenario.
Production source is unchanged, so this gate does not claim a new full
library or non-Linux runtime qualification. The rejected conditional-wake
experiment is separately recorded in ../2026-11-01-progress-wakeup/.
