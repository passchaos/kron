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
| Pre-rewrite backup branch | removed after verification |
| Pre-rewrite bundle | `/nav_env/project-z/kron-pre-evidence-rewrite.bundle` (not in Git) |
| Tracked size after rewrite | about 156 MiB / 14,628 files |
| Tracked size before rewrite | about 216 MiB / 14,851 files |
| Pack size before rewrite | 76.34 MiB |
| Pack size after reflog expiry + gc | 25.26 MiB |
| Fresh remote clone `.git` | 29 MiB (pack 25.82 MiB) |

All commit SHAs before the rewrite are invalid. Use the bundle when an old SHA
must be inspected. The temporary backup branch was deleted after the rewritten
`main` passed the full test suite and a fresh clone was measured.

## Boundary

The rewrite removes only repository storage. It does not change source code,
journal formats, benchmark results or the evidence READMEs. The same
`manifest.json` files still record binary/source SHA-256 identities, so removed
executables and archives remain reproducible from their recorded commands.
