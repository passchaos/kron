# Contributing

Thanks for improving kron. The project is a Zig 0.16 logging library with
explicit ownership, bounded queues and a large benchmark evidence set.

## Before changing code

- Read [docs/code-structure.md](docs/code-structure.md) for module ownership and
  the evaluated split boundaries.
- Read [docs/development.md](docs/development.md) for the minimal verification
  command for your change.
- Read [docs/benchmark-evidence-policy.md](docs/benchmark-evidence-policy.md)
  before adding or moving benchmark evidence.

## Verification

Start small, then broaden only when the change touches public APIs, build
packaging, concurrency/lifetime, persistent formats or cross-platform paths:

```sh
zig build test-unit -Doptimize=ReleaseSafe -j1
zig build test-logging -Doptimize=ReleaseSafe -j1
zig build verify-fast -Doptimize=ReleaseSafe -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build fmt bench-index hygiene docs -j1
```

Keep unit tests close to the logic they exercise. Put integration, fault,
compile-fail and package-consumer tests under `tests/` or the owning module.

## Evidence and repository hygiene

- New benchmark evidence uses
  [bench/evidence/TEMPLATE.md](bench/evidence/TEMPLATE.md).
- Refresh the index with `python3 tools/bench_index.py`.
- Do not track compiled references, tar snapshots or raw `perf.data`/`data`
  files; record SHA-256 and commands in `manifest.json`.
- Run `zig build hygiene` before committing.

## Commits

Keep unrelated changes in separate commits. After a verified functional change,
commit, rebase on the remote branch, resolve conflicts, re-run the relevant
verification, and push. The project is MIT licensed; contributions are accepted
under the same license.
