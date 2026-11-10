# Changelog

All notable changes to this project are documented here. The version follows
`build.zig.zon`; the project is pre-1.0, so public APIs may still change with a
verification note.

## Unreleased

### Changed

- Source distribution carries benchmark sources and scripts, but excludes
  `bench/evidence/` and `bench/cpp_reference/evidence/`.
- README and `docs/implementation-status.md` keep current state; detailed
  performance chronology moved to `docs/history/`.
- Runtime route/channel limits use shared constants instead of 64/65 literals.
- The optional global logging owner uses an atomic acquire/release slot.
- Rewrote `main` history to remove reference binaries, tar snapshots and raw
  profiling data; pre-rewrite history is preserved in the temporary
  `backup/pre-evidence-rewrite` branch and
  `/tmp/kron-pre-evidence-rewrite.bundle`.

### Added

- MIT license.
- Generated benchmark evidence index (`bench/evidence/INDEX.md`) and experiment
  template.
- `zig build fmt`, `bench-index`, `hygiene`, `docs` and `verify-fast` steps.
- Repository hygiene guard and GitHub Actions CI.
- `docs/history/readme-performance-2026-11-09.md` and
  `docs/history/verification-chronology-2026-11-09.md` snapshots.

### Fixed

- Restored the missing x86_64 pre-V3 journal fixtures, generated from the same
  `5b1fd7c` worktree; all four fixture cases now run in the test suite.

### Removed

- Tracked benchmark reference executables under `bench/evidence/`; their
  identity remains in each experiment's `manifest.json` (`binary_sha256`).

## 0.1.0 - 2026-11-01

- Initial kron source import: structured logging, bounded Memory/Mmap queues,
  text/JSON/logfmt/binary encoders, rolling files, configuration, sampling,
  redaction, archive reader and recovery boundaries.
