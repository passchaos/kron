# Benchmark measurement policy

Benchmark sources and analysis scripts are part of the project, but measured
results are not source code. This repository tracks the harnesses, methodology,
and reviewed summaries; it does not track raw measurement directories, generated
artifacts, or frozen reference-implementation sources.

## Tracked

- `bench/` harnesses and analysis scripts.
- `docs/benchmark-methodology.md` and this policy.
- Reviewed performance summaries in `docs/implementation-status.md` and
  `docs/history/`, including their source revision and limitations.

## Not tracked

- Benchmark result directories, raw `results.jsonl` files, manifests, and
  generated comparison reports.
- Compiled benchmark or reference binaries.
- `*.tar`, `*.tar.xz`, `*.tar.gz` source snapshots.
- `*.perf.data`, `*.perf.data.gz`, `*.data` profiling data.
- Frozen C++/Rust reference sources and generated workload files.

If a result must be preserved externally, store it outside Git together with the
source revision, binary/source SHA-256, exact build/run command, host, and
workload identity so it can be regenerated.

## Running a measurement

1. Build the relevant executable from a clean, identified source revision.
2. Record the source revision, binary hash, toolchain, host, CPU affinity,
   workload, budgets, and actual backend.
3. Verify every complete record and the written/durable completion boundary.
4. Keep failures, slow values, and inconclusive results in the external record;
   do not retain only favorable rows.
5. Run `python3 tools/check_repo_hygiene.py` and `zig build hygiene` before
   committing.

## History boundary

On 2026-11-10 `main` history was rewritten to remove reference binaries, tar
snapshots, and raw profiling data. The pre-rewrite history is preserved in
`/nav_env/project-z/kron-pre-evidence-rewrite.bundle` outside Git; details and
old/new sizes are in
[repository-history-rewrite-2026-11-10.md](history/repository-history-rewrite-2026-11-10.md).
On 2026-11-10 the tracked benchmark evidence directories and C++/Rust reference
harnesses were removed from the current tree.
