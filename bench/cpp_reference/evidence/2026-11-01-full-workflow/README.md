# Complete C++ / Foundation / kron workflows

The main matrix compares spdlog 1.17.0, Quill 13.1.0, the requested local
Foundation Logging owning C++/Rust sources, and current kron. It runs 260 trials:
13 configurations, one/four producers, separate sampled/batch processes and
five repetitions. Each trial verifies 100,000 measured records and 1,000 warmup
records, totaling **26,260,000 complete records**. Every case passed.

All main outputs have the same full JSON field layout, five u64 attributes and
system wall-clock timestamp. Record sizes are about 299 bytes. Fixed child
affinity selects CPUs 0/2/4/6/8/10 on an i9-13900K Linux host, and actual files
are written to NVMe ext4. C++ uses GCC13.3 O3, kron uses Zig0.16 ReleaseFast on
both modules, and Foundation uses its locked Rust release core.

The interval to written flush includes producer work, backend formatting and
file output. Total completion further includes shutdown/join, remaining owner
cleanup and file close. Initialization and preparation are reported separately;
the whole library lifecycle includes both. Quantiles time the producer call,
not per-record final visibility. Output rereading and validation happen after
measurement. No interval requests durable media synchronization.

Foundation uses its actual Logger.Native/Flush/Close, with no second async
queue. The common JSON layout uses a public formatter; this excludes its
optimized default text formatter. A separate **40-trial control** uses the
original default formatter and verifies **4,040,000 complete records**. That
output is about 175 bytes/record and is not ranked against the 299-byte common
JSON workload. Both controls keep the same explicit queue and file buffers.

`comparison.md` gives the complete main tables; `analysis.json` contains each
metric's median/min/max/spread and 10% noise-limit result. The `foundation-default-*`
files retain the control. All completed outliers are included. Most complete
performance comparisons remain inconclusive as stable regression qualifications,
even when their medians show substantial gaps.

`manifest.json` retains exact build commands, library pins/include hashes,
compiler/host/filesystem information and binaries' SHA256. `measured-source.tar.gz`
includes the **exact main measured harness**, kron production src and frozen
Foundation sources. Its reference.cpp/run.py hashes match the original manifest;
later default-format control/validation extensions are separate source versions.
Upstream source archives were checked against pinned SHA256. Foundation source
matches onboard-monorepo HEAD `0d1f5b0c5689a3fdc502b1c4c7ed8496eb1d5a94`.

Original output files were independently verified before cleanup; per-trial
file hashes, physical newline counts, byte counts and event counts are retained.
Remove `--discard-artifacts` to preserve logs in future runs (about 8GB for this
main matrix). Failed trial artifacts would be retained and prevent a passing
analysis; none failed in this run.

```sh
python3 bench/cpp_reference/run.py \
  --deps-dir /tmp/kron-cpp-bench-deps --output-dir /tmp/kron-cpp-workflow \
  --libraries spdlog,quill,foundation,kron --events 100000 --warmup 1000 \
  --repeats 5 --producers 1,4 --kron-storages memory,mmap \
  --kron-schema both --metadata full --affinity auto --discard-artifacts
python3 bench/cpp_reference/analyze.py /tmp/kron-cpp-workflow
zig build test-cpp-reference-report -j1
```

The current harness also passed a 52-trial small/uneven-ID smoke and four negative
verification tests. `qualification.json` binds reports, exact measured sources
and final validation identities. See [the detailed result and limitations](../../../../docs/cpp-full-workflow.md).
