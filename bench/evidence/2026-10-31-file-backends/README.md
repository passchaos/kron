# File backend pilot, 2026-10-31

Three alternating-order repetitions of the same ReleaseFast Zig 0.16 executable,
shared async journal, four producers, five numeric fields, JSON Lines, 10,000
total measured attempts per phase, and 1,000 total excluded warmup attempts.
Both backends use 64 KiB batches, queue depth 4, 256 journal slots, a 16 KiB
record bound, the block overload policy, and runtime-default sleeping idle.
The rate includes every measured producer, final written flush, and shutdown.

Raw results and exact commands are in `results.jsonl`; binary SHA-256, CPU and
kernel information, affinity, filesystem/block-device metadata, and capture
timestamp are in `machine.json`. Output was on ext4 on `/dev/nvme0n1p2` with
`rw,relatime,errors=remount-ro` mount options.
`summary.json` reports three-trial median/min/max values. Log/journal artifacts
were checked at capture and remain under the original `/tmp` evidence directory;
they are not copied into the repository. Paths in the raw report are the original
artifact paths and may cease to exist after temporary storage cleanup.

| Backend | Sampled median written records/s | Batch median written records/s | Sampled median p50 | Sampled median p99 | Sampled median p99.9 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Portable | 619,537 | 598,961 | 1,125 ns | 87,407 ns | 103,275 ns |
| Linux io_uring | 551,960 | 568,293 | 1,150 ns | 97,143 ns | 111,174 ns |

Every row confirmed 10,000 accepted and 10,000 written records with zero pending
and zero write errors. The io_uring rows actually selected and ran io_uring.
The large p99 relative to p50 includes bounded-journal backpressure under four
concurrent producers; it is not a clock-baseline-adjusted frontend estimate.

The host was not reserved or affinity-pinned, and source development was still
ongoing. These are bounded pilot observations, not an established regression
baseline or a default-backend recommendation. The binary hash fixes the measured
artifact; `git_revision` is null because this workspace had no Git repository at
capture. Repeat on a controlled machine and record filesystem/storage details
before drawing a hardware-independent performance conclusion.

Reproduce with a freshly built executable:

```sh
python3 bench/compare_backends.py --binary /tmp/kron-bench \
  --output-dir /tmp/kron-bench-file-comparison --repeats 3 \
  --events 10000 --mode async --producers 4 --fields 5 --payload numeric
```
