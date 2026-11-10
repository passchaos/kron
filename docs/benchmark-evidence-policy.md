# Benchmark evidence policy

Benchmark evidence is part of the project, but raw measurement machinery is not
source code. The repository keeps the identity, commands and reviewed results;
large regenerable artifacts stay outside Git.

## Tracked

- `README.md`: experiment question, completion boundary, result and limitations.
- `manifest.json`: host, source/binary SHA-256, commands, configuration and
  measured workload.
- `results.jsonl` (or a compressed `results.jsonl.xz`): raw measurement rows.
- `comparison.md`, `summary.json`, `analysis.json` when they are the reviewed
  interpretation.
- patches, small provenance JSON and curated logs needed to explain a failure.
- frozen source snapshots only when they cannot be identified by commit SHA and
  a patch; prefer one content-addressed snapshot over one copy per experiment.

## Not tracked

- compiled reference binaries (`reference-*`)
- `*.tar`, `*.tar.xz`, `*.tar.gz` source snapshots
- `*.perf.data`, `*.perf.data.gz`, `*.data` profiling data
- generated workload files, caches and `kron-bench-*`/`kron-ref-*`/`kron-crc-*`
  outputs

The corresponding `manifest.json` must retain the binary/source SHA-256 and the
exact build/run command, so the artifact can be regenerated or fetched from an
external store.

## Adding evidence

1. Copy [TEMPLATE.md](../bench/evidence/TEMPLATE.md) into
   `bench/evidence/<date>-<name>/`.
2. Keep the experiment directory self-contained: README, manifest and raw rows.
3. Run `python3 tools/bench_index.py` to refresh `bench/evidence/INDEX.md`.
4. Run `python3 tools/check_repo_hygiene.py` and `zig build hygiene`.
5. Do not rewrite old evidence when moving directories; update links and record
   the move in the README.

## History boundary

On 2026-11-10 `main` history was rewritten to remove reference binaries, tar
snapshots and raw profiling data. The pre-rewrite history is preserved in
`/nav_env/project-z/kron-pre-evidence-rewrite.bundle` outside Git; details and
old/new sizes are in
[repository-history-rewrite-2026-11-10.md](history/repository-history-rewrite-2026-11-10.md).
