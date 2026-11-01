# Same-round cross-library smoke (not a ranking)

This directory records a harness smoke run of `bench/cpp_reference/run.py`
against the current kron source and the pinned local Foundation source. It
validated that both binaries build and every output record passes the oracle.

It is **not** a performance comparison. The host load average was about 109
during the run. Foundation reported an 8.7-second initialization and a
6.6-second shutdown in one configuration, collapsing the lifecycle throughput
to about 1.5K records/s. Those values are host I/O/scheduler noise, not a
Foundation capability measurement. `summary.json` marks every group
inconclusive.

A formal same-round comparison still requires a quieter window: five
alternating repetitions per configuration, fixed physical-core affinity, and
the same complete JSON/written-flush/shutdown/cleanup endpoints. Until then,
the archived 2026-11-01 full-workflow numbers and the current PCLMUL evidence
must not be combined into a new ranking.

Files:

- `manifest.json`, `summary.json`, `results.jsonl` — the exact smoke capture.
