# Current Memory/Mmap full file workflow

Measured kron commit `182fc9e`, default `consumer_batches_per_queue=4`.
This same-round capture only compares Foundation Memory/Mmap and kron
shared/SPSC Memory/Mmap, each at one and four producers. Foundation is the
real C++/spdlog frontend, `cpp/src/logger.cc` and Rust logging core; it is
not the standalone spdlog async reference. The public formatter extension
point provides the identical full JSON field layout.

`measured-source.tar.gz` freezes the complete kron production tree and actual
Zig/C++ harness, runner/analyzer and version pins. `foundation-source.tar.gz`
retains the exact copied C++/Rust source compiled for this run; its tree hash
was verified before archiving. `manifest.json` has dependency/source/binary
hashes, compilers, CPU topology, ext4/filesystem and build commands;
`capture.json` records commit, archive hashes and host load observations.

## Capture and completion boundaries

**120/120 formal trials**, **12,120,000 physical JSON records** independently
verified (12M measured, 120k warmup). Every trial accepts/writes100000 measured
records and has drop/pending0, complete newline framing, unique IDs, exact
five numeric attributes and physical file byte counts. Output files are
deleted only after successful independent oracle verification; per-file
hashes and counters remain in `results.jsonl`. All kron rows confirm default4.

Linux x86_64/i9-13900K, NVMe ext4, Zig0.16 ReleaseFast, C++-O3 and Rust
release. Child affinity CPU0/2/4/6/8/10. Each group has five independent
sampled and five batch trials, rotated/reversed execution order. System
wall clock, one real file, complete JSON of about299 bytes/event,256 slots,
64KiB file buffer, blocking overflow, no predicate/sampling/rotation/compression.
Kron has typed capture and backend JSON rendering; Foundation preserves its
real spdlog frontend and Rust memory/spool backend. SPSC reserves additional
channel queues and reports their total bytes; memory bounds are not claimed
to be identical across layouts. There is no fsync/durable media flush.

`written_close` includes producer, background encode/file write, final written
flush, shutdown and file/object cleanup. `written_flush` excludes close.
`lifecycle` further includes file/logger/queue initialization, producer startup
and1000 warmup records. Metrics remain separate; medians of phases must not
be added to reconstruct an individual lifecycle.

## Throughput and qualification

Five batch-process medians, millions of records/second, through final close:

| Storage/configuration | P1 | P4 |
| --- | ---: | ---: |
| Foundation Memory |1.932|1.990|
| kron shared Memory |2.136|2.063|
| kron SPSC Memory |2.151|2.106|
| Foundation Mmap |1.789|2.097|
| kron shared Mmap |2.107|1.741|
| kron SPSC Mmap |2.157|1.911|

Memory kron medians are above Foundation in this window (P1 roughly11%,
P4 shared3.7%/SPSC5.8%). Mmap P1 medians are roughly18%/21% above
Foundation, while P4 shared17.0% and SPSC8.9% are below it. All Foundation
through-close groups exceed the10% repeatability threshold; only kron
SPSC Memory P4 is within it (spread3.6%). A stable single-library group
cannot establish a stable cross-library advantage when its peer is noisy.
This run does **not** qualify comprehensive superiority in both storage modes.

The actual full-lifecycle medians for a100k trial further show cold costs:

| Configuration | P1 init ms | P4 init ms | P1 lifecycle ms | P4 lifecycle ms |
| --- | ---: | ---: | ---: | ---: |
| Foundation Memory |0.23|0.21|52.60|51.31|
| kron shared Memory |0.62|0.59|48.16|50.10|
| kron SPSC Memory |0.89|0.96|48.47|49.11|
| Foundation Mmap |22.67|13.01|79.51|62.04|
| kron shared Mmap |5.65|21.42|55.18|86.25|
| kron SPSC Mmap |23.88|368.10|68.78|446.39|

Mmap startup is highly variable; every slow observation remains retained.
The SPSC P4 Mmap lifecycle is much higher in this window. Five mappings,
preallocation and persisted header/file/directory publication are part of
kron's startup protocol. Earlier syscall tracing confirms substantial
msync/fsync wait in an individual slow startup; the trace is diagnostic,
not a proof that all difference comes from one syscall or library.

Sampled P4 producer-call p99.9 medians: Foundation Memory66.1us, Mmap18.8us;
kron SPSC Memory387.0us, Mmap372.2us. These are producer attempt samples,
not final write-visible latency. Tail values fluctuate, and SPSC's short
p50 does not prove a better whole workflow. `analysis.json` records all
min/max/spread and per-metric qualifications; `comparison.md` is a generated
summary, and cannot replace those limits. The optional quantum1 experiment
has separate p99/p99.9 tradeoff data and is not mixed into this default4 rank.

## Reproduction

```sh
python3 bench/cpp_reference/run.py \
  --output-dir /path/to/fresh-capture --libraries foundation,kron \
  --events 100000 --warmup 1000 --repeats 5 --producers 1,4 \
  --metadata full --kron-schema off --kron-modes async,spsc \
  --kron-storages memory,mmap --affinity auto --discard-artifacts
python3 bench/cpp_reference/analyze.py /path/to/fresh-capture
```

Source/binary hashes lock the measured snapshot;
future production changes require a new same-round capture. Stable host
windows, mmap lifecycle reduction and saturated SPSC tail qualification
remain part of the active library goal.
