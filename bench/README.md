# Performance benchmarks and navigation

Read [benchmark methodology](../docs/benchmark-methodology.md) first: it
distinguishes producer quantiles, written completion, durability,
initialization/warmup/shutdown/cleanup, and queue/output storage modes.
Measurements record source/binary identity, inputs, budgets, complete-record
verification, failures, and noise; results without sufficient repeatability are
reported as inconclusive.

## Main entry points

| Purpose | Entry point/description |
| --- | --- |
| Complete logging workflow | [main.zig](main.zig), `zig build bench -Doptimize=ReleaseFast -- --mode=async --storage=memory --producers=4 --sink=file --backend=portable` |
| Application computation and no-logger baseline | [application.zig](application.zig), [application notes](../docs/application-benchmark.md), [comparison script](application_compare.py) |
| Controlled repetition and regression | [regression.py](regression.py), [regression method](../docs/performance-regression.md) |
| Main-program output verification | [validate.py](validate.py) |
| Runtime request memory and thread budgets | [runtime_resources.zig](runtime_resources.zig), `zig build bench-runtime-resources -Doptimize=ReleaseFast -- memory /tmp/existing-directory 0`; does not cover all OS resources |
| Clock, capture, schema, filter, and other local costs | `bench-dispatch`, `bench-capture`, `bench-snapshot`, `bench-sampling`, `bench-encoding`, `bench-regex`, `bench-time`; see topic documents for commands |

## Measurements

Measured results are no longer tracked in this repository. The benchmark sources
and analysis scripts remain, and the conclusions that survived review are in
[performance hotspots](../docs/performance-hotspots.md),
[industry optimization lessons](../docs/industry-performance-lessons.md),
[current acceptance status](../docs/implementation-status.md), and
[history](../docs/history/README.md). New measurements should be stored outside
Git with source/binary hashes, commands, host identity, workload, budgets, and
all failures/slow values.

`managed_outputs.zig` measures single- and dual-output complete workflows through
the managed entry, separating initialization, producer submission, and
written/shutdown time; it covers sync/Memory/Mmap/SPSC.
`managed_outputs_compare.py` runs paired before/after rotations, verifies every
actual file JSON record, and reports confidence intervals. Usage:
`zig build bench-managed-outputs -Doptimize=ReleaseFast -- memory /tmp/existing-directory 20000 2`
(the trailing output count defaults to 1 and may be 2). The comparison script's
`--outputs=2` verifies both complete JSON files and total written, with
per-output sequence and configuration metadata in the oracle. Independent
multi-output pipelines add queue, background-thread, and encoding cost; a
single-output number does not represent multi-output throughput.
