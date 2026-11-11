# Changelog

All notable changes to this project are documented here. The version follows
`build.zig.zon`; the project is pre-1.0, so public APIs may still change with a
verification note.

## Unreleased

### Changed

- Source distribution carries benchmark sources and scripts, but no measured
  results or frozen reference-implementation sources.
- README and `docs/implementation-status.md` describe current state; detailed
  performance chronology remains under `docs/history/`.
- Runtime route/channel limits use shared constants instead of 64/65 literals.
- The optional global logging owner uses an atomic acquire/release slot.
- Extracted pure TSC calibration math into `src/platform/tsc_math.zig`; clock
  state, cross-core probe, and fallback remain in `tsc_clock.zig`.
- Extracted cold route payload construction and comparison into
  `src/config/routes_payload.zig`; the Snapshot/Manager hot path remains in
  `routes.zig`.
- Documentation is written in English.

### Added

- MIT license.
- CONTRIBUTING.md and SECURITY.md.
- Capability matrix for mode/storage/format/recovery/durable combinations.
- Benchmark retention policy and history-rewrite boundary.
- `zig build fmt`, `hygiene`, `links`, `docs`, `test-unit`, and `verify-fast`
  steps.
- Repository hygiene guard and GitHub Actions CI, including docs, Markdown
  links, compile-fail/fuzz/decoder/single-threaded gates, regex
  differential/fuzz/equivalence gates, benchmark/report self-tests,
  cross-platform compile checks, native platform-host qualification, package
  distribution/single-threaded consumer, and crash/recovery gates. CI uses
  read-only permissions, superseded-run cancellation, and Zig build caching.
  Coverage boundaries are documented in `docs/development.md`.
- `docs/history/readme-performance-2026-11-09.md` and
  `docs/history/verification-chronology-2026-11-09.md` snapshots.
- Optional glog-style `FailureHandler`: fatal-signal capture for
  SIGSEGV/SIGILL/SIGFPE/SIGABRT/SIGBUS/SIGTERM, UTC crash-file naming,
  raw stack addresses, stderr mirroring, a stable `<program>.FATAL` symlink,
  `record`/`fatal` entry points, and an opt-in `Logging` `.fatal` hook.
  Signal reports include symbolized traces by default; the raw report is
  written to the file before symbolization, and `segv-raw` verifies the opt-out.
  Reports are built in one fixed buffer, written to the file before the stderr
  mirror, and `fsync` is opt-in. `install` opens the crash directory once
  so relative directories survive `chdir`. Real-child verification is available
  through `test-failure-handler`.
- Runnable `run-failure-handler` example for non-fatal reports and real
  `segv`/`fatal`/`fatal-log` crash modes.

### Fixed

- Restored the missing x86_64 pre-V3 journal fixtures, generated from the same
  `5b1fd7c` worktree; all four fixture cases now run in the test suite.

### Removed

- C++ and Rust cross-library benchmark harnesses, including the spdlog, Quill,
  Foundation, and Foundation tracing reference programs.
- Frozen Foundation C++/Rust source snapshots and all benchmark evidence
  directories under `bench/evidence/` and `bench/cpp_reference/evidence/`.
- C++ comparison drivers, analyzers, qualification scripts, report self-tests,
  the generated evidence index, and the `bench-index` build step.

## 0.1.0 - 2026-11-01

- Initial kron source import: structured logging, bounded Memory/Mmap queues,
  text/JSON/logfmt/binary encoders, rolling files, configuration, sampling,
  redaction, archive reader, and recovery boundaries.
