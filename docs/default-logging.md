# Using kron as a Zig project's default logger

kron can serve as the default logging implementation for Linux single-machine
applications pinned to Zig 0.16. Structured output, filtering and hot
configuration, redaction, sync/shared-async/SPSC, file rotation, archives, and
process recovery all have real execution and error-boundary gates. Applications
must explicitly choose queue budgets, overload policy, and shutdown behavior, and
pin the dependency version; the current package version is 0.1.0, and future API
compatibility is not promised.

Start with `kron.Logging`, a shared asynchronous Memory queue, the portable file
backend, and text/JSON output. It uniformly manages all configured outputs and the
underlying Runtime, covering the usual single-machine application pattern. See
[quick_start.zig](../examples/quick_start.zig) for a minimal program,
[file_logging.zig](../examples/file_logging.zig) for background file logging, and
the [detailed usage guide](usage.md) for all parameters and thread/context
lifetime. The default `.{}` logs synchronously to stderr; services should
explicitly set `.mode = .asynchronous` on each route.

Ordinary services should use shared Memory/Mmap as the main path; a normal
`scoped` logger is sufficient for multiple producers and usually does not need
SPSC or thread attachment. SPSC remains an advanced option for fixed OS threads:
per-thread queues add space and Mmap preparation cost, task migration is
restricted, and p99.9 currently has no general advantage. Adopt it only after the
application measures a benefit.

Configure parameters according to application needs:

| Requirement | Recommendation |
| --- | --- |
| Small tool or single-threaded application | Sync mode, with explicit flush/shutdown error handling |
| Background file logging | Shared async Memory, fixed slot and record budgets, portable backend |
| Limit logging's blocking impact on the application | Choose `drop_newest` according to business needs and monitor drops/errors; `block` waits on a full queue |
| Recover accepted-but-undelivered events after process stop | Mmap journal, stable output identity, accepting initialization/disk budget and at-least-once duplication |
| Very high frequency, fixed thread count, measured shared contention | Explicit SPSC attachment, verifying p99/p99.9 and total queue retention separately |
| Confirm resistance to system power loss | Explicit durable plus actual platform/filesystem qualification; written or Memory accepted are not substitutes |
| Integrate existing `std.log` calls | Use `kron.Logging.std_log` in root `std_options`, call `bindStdLog`, and `unbindStdLog` before shutdown |

Application lifetime order: create I/O and Logging, start producers; stop all
logger/token users and detach, unbind `std.log`, explicitly flush/shutdown,
destroy Logging and I/O. When using the advanced Runtime directly, also ensure
Runtime is destroyed before the sink. Use `tryEmit`/flush/shutdown results when
errors must be observed; ordinary void logging should still monitor background
failures through health/error callbacks. The `std.log` bridge has its own
unbound/oversize/error statistics and should be bound before application logging
starts; it uses a bounded producer formatting buffer and does not have the typed
path's deferred-formatting performance.

Choosing kron as a project default does not require beating every benchmark
competitor. For an actual release, test backpressure, shutdown, and output
completeness on the application's target workload. Known limits include SPSC
saturation p99.9 around 340 µs, Mmap cold-start/channel preparation cost, and
schema throughput/tail trade-offs; choose defaults from the application's log
frequency and reliability requirements, not from a local median improvement.

Windows/macOS/Android/iOS currently have implementations and cross-compilation or
partial-link evidence but still lack real-device logging/lifecycle/journal
recovery qualification. Cross-platform production applications should first run
the target-device self-check in `tests/package_consumer/platform.zig` and add
their own fault scenarios. Long-running fuzz/sanitizers, multi-filesystem
power-loss testing, and broader business-workload qualification remain tracked in
`implementation-status.md`.

Entry points: [detailed usage guide](usage.md), [Zig package](package.md),
[lifecycle](lifecycle.md), [platform qualification](platforms.md),
[std.log example](../examples/std_log.zig).
