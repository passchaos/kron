# Repository history rewrite (2026-11-10)

`main` history was rewritten with `git filter-repo` to remove raw benchmark
artifacts that had accumulated in every commit:

- `reference-*` executable copies under `bench/evidence/` and
  `bench/cpp_reference/evidence/`
- `*.tar`, `*.tar.xz`, `*.tar.gz` source snapshots
- `*.perf.data`, `*.perf.data.gz` and `*.data` profiling data
- `kron-bench-*`, `kron-ref-*`, `kron-crc-*` generated benchmark outputs

`*.perf.data.xz` (11 small compressed profiles), logs, JSONL/JSON measurement
rows, CSV rows, patches and evidence READMEs remain tracked so existing evidence
links and raw measurement identity stay available.

## Identity

| Item | Value |
| --- | --- |
| Pre-rewrite `main` | `ce96b6e` |
| Rewritten `main` at rewrite time | `5952ec1a` |
| Pre-rewrite backup branch | `backup/pre-evidence-rewrite` (temporary) |
| Pre-rewrite bundle | `/tmp/kron-pre-evidence-rewrite.bundle` (not in Git) |
| Tracked size after rewrite | about 156 MiB / 14,627 files |
| Tracked size before rewrite | about 216 MiB / 14,851 files |

All commit SHAs before the rewrite are invalid. Use the backup branch or the
bundle when an old SHA must be inspected; the branch can be deleted after the
rewritten `main` has been verified and mirrored.

## Boundary

The rewrite removes only repository storage. It does not change source code,
journal formats, benchmark results or the evidence READMEs. The same
`manifest.json` files still record binary/source SHA-256 identities, so removed
executables and archives remain reproducible from their recorded commands.
