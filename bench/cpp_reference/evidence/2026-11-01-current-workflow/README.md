# Current full file workflow: Foundation/standalone spdlog/kron

Measured kron Git commit: `4447fe6`. `measured-source.tar.gz` freezes all
kron production source and the actual C++/Zig harness, runner, analyzer and
dependency version pins. `capture.json` records its SHA256 and load samples.
`foundation-source.tar.gz` retains the exact copied Foundation C++/Rust
source used to compile; its unpacked tree hash was checked against the
manifest before archiving. Dependency/include and binary hashes, compiler
versions, filesystem and CPU topology are in `manifest.json`.

The real Foundation path uses its public Logger.Native()/spdlog C++ front
end, `cpp/src/logger.cc` and the Rust logging core. Standalone spdlog 1.17.0
uses its own asynchronous logger; it is a separate case. No local owning
Foundation sources were edited. The common full JSON formatter uses the
public customization point and retains system-clock timestamps, stable
event identity and all five numeric attributes.

## Completed capture

**140/140 trials** complete and independently verify **14,140,000 physical
JSON records** (14,000,000 measured records plus 140,000 warmup records).
Every trial accepts/writes 100000 measured records, reports pending/drop=0,
and validates IDs, attributes, full newline records and physical bytes after
close. `run.log`, `results.jsonl`, `manifest.json`, `summary.json`,
`analysis.json` and `comparison.md` retain the full results. Verified output
files are discarded only after the oracle succeeds; their hashes and counts
remain in each trial report.

Linux x86_64, i9-13900K, NVMe ext4, Zig 0.16 ReleaseFast, C++ -O3 and Rust
release. Child affinity is CPU 0/2/4/6/8/10. Each group has five independent
repetitions with alternating/rotated library order; both sampled and batch
trials run. Common settings: one real file target, 64KiB output buffer, block
queue, 256 slots, system wall clock, about 299 bytes/event. Kron uses inline
metadata, shared async and per-thread SPSC, memory/mmap separately. SPSC has
additional per-producer channels; the different total queue/file budgets
remain reported rather than hidden. There is no predicate/sampling,
rotation, compression or durable media flush in this workload.

## Result and qualification

Median throughput in millions of records/second below includes producer,
background format/write, final written flush, shutdown and object/file cleanup.
Initialization/preparation remain separate; the lifecycle column includes
both, plus 1000 warmup records, for a 100k-record trial.

| Configuration | P1 through close | P4 through close | P4 full lifecycle ms |
| --- | ---: | ---: | ---: |
| Foundation memory | 2.116 | 2.309 | 44.17 |
| Foundation mmap | 1.800 | 2.079 | 58.09 |
| spdlog async | 1.640 | 0.673 | 149.91 |
| kron async memory | 2.141 | 2.064 | 49.73 |
| kron async mmap | 2.188 | 2.075 | 70.45 |
| kron SPSC memory | 2.174 | 2.108 | 49.08 |
| kron SPSC mmap | 2.251 | 2.117 | 107.38 |

Kron's medians exceed standalone spdlog in this workload, but spdlog's
relative spread is 27.6%/22.0% for P1/P4, beyond the 10% stability budget.
No universal or stable multiplier is qualified. Foundation P4 memory still
has the higher median (kron SPSC memory is 8.7% lower). P4 mmap close
throughput is close: kron SPSC is 1.8% higher, smaller than Foundation's 8.3%
spread, so it does not establish an advantage. P1 mmap SPSC has the higher
median, while Foundation P1 mmap spread is 38.2%, leaving the cross-library
ranking inconclusive. P1 async memory is only 1.2% above Foundation, with
7.7%/8.6% spread respectively.

Cold/lifecycle costs remain material: P4 SPSC mmap takes about 107ms versus
Foundation's 58ms for the median full lifecycle. Mmap initialization and
some shutdown tails vary substantially; all slow samples remain in the
reports. A stable group under the 10% spread budget means only local
repeatability of that metric, not a confidence interval proving cross-library
dominance. The host remained heavily loaded (load samples are in
`capture.json`). This run does **not** prove kron comprehensively exceeds
the Foundation+spdlog pipeline, nor all logging workloads.

The regex closure improvement from `4447fe6` has separate predicate-workload
evidence. This cross-library workload disables predicates and cannot assign
its before/after differences to that regex change. It verifies the current
whole library rather than adding earlier local percentage improvements to
old cross-library results.

## Reproduce

```sh
python3 bench/cpp_reference/run.py \
  --output-dir /path/to/fresh-capture --libraries foundation,spdlog,kron \
  --events 100000 --warmup 1000 --repeats 5 --producers 1,4 \
  --metadata full --kron-schema off --kron-modes async,spsc \
  --kron-storages memory,mmap --affinity auto --discard-artifacts
python3 bench/cpp_reference/analyze.py /path/to/fresh-capture
```

`written_flush` excludes close, `written_close` includes close, and
`lifecycle` includes initialization/preparation; never mix their rankings.
Neither written metric requests fsync/fdatasync or strict device durability.
The larger goal's remaining platform, fault and stable-performance
qualifications remain in `docs/implementation-status.md`.
