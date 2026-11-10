> Historical snapshot before reorganization; source baseline `7e98358`. See
> [documentation navigation](../README.md) for the current interface and status.

# kron

A logging library for Zig 0.16, targeting low call latency, structured events,
readable output, and explicit crash-recovery semantics.

It provides single-machine logging on Windows, Linux, macOS, Android, and iOS:
synchronous, Memory-async, and mmap-async submission; text/JSON; dynamic
filtering; file rotation; archives; recovery; and performance verification.
Network sinks and exporters have been removed. See the
[implementation acceptance checklist](../implementation-status.md) for evidence
and remaining work.

The public interface is Zig-only; see [Zig package integration](../package.md)
for package dependencies and application lifetime.

Common integration uses `kron.Logging`, which manages one or more outputs and the
underlying Runtime; the default is stderr, synchronous, text, info. See the
[detailed usage guide](../usage.md) for parameters, structured fields, threads,
Memory/Mmap, the `std.log` bridge, rotation, and error handling.

```zig
const logging = try kron.Logging.create(init.gpa, init.io, .{});
defer logging.destroy();
const log = logging.scoped("app");
log.info("started", .{ .version = "1.0" });
try logging.shutdown();
```

Here `init` is Zig 0.16's `std.process.Init`, and the application imports
`const kron = @import("kron")`. See
[quick_start.zig](../../examples/quick_start.zig) for a complete program.
Background file logging sets `.output = .{ .file = .{ .path = "app.jsonl", .backend = .portable } }`,
`.mode = .asynchronous`, and `.format = .json`; the default is a bounded Memory
queue. See [file_logging.zig](../../examples/file_logging.zig).

Linux single-machine projects pinned to Zig 0.16 can use kron as the project
default, preferring shared async Memory and the portable file backend, choosing
an overload policy, and shutting down explicitly. See
[default logging advice](../default-logging.md) for selection, the `std.log`
bridge, and qualification boundaries.

See [overall design](../design.md) for the complete design, including the
multi-language logging survey and final decisions on performance, mmap, io_uring,
dynamic filtering, and reliability.

## Core direction

- Structured events first, with typed fields, context, redaction, and trace
  correlation.
- Default output is plain text or JSON Lines, viewable directly and compatible
  with existing log collection systems.
- Asynchronous mode offers two storages: `memory_queue` uses fixed memory, and
  `journal` uses a file-backed shared mmap; the background formats and writes
  uniformly.
- Ordinary loggers use a shared bounded queue; explicitly registered low-latency
  loggers use per-thread SPSC channels, either with Memory or mmap.
- Recover complete committed but unwritten records after a process crash without
  relying on a crash handler to drain an ordinary Memory queue.
- Distinguish `accepted`, `written`, and `durable`; power-loss resistance requires
  synchronous durable confirmation.
- Linux provides an optional io_uring batched-write backend while retaining the
  ordinary batched-write backend.
- Support environment variables, runtime APIs, and hot configuration reload;
  common filters do not parse configuration or read environment variables per
  log.
- Memory, journal space, thread channels, and in-flight I/O all have explicit
  budgets.

## Configuration example

```bash
KRON_LOG='info,http=debug,db.query=trace,noisy=off' ./app
```

A running process updates rules through an explicit reload/API; changing the
environment variable in another shell does not affect an already running
process.

## Build and run

```bash
zig build
zig build verify-local -Doptimize=ReleaseSafe -j2
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build test-package -Doptimize=ReleaseSafe -j1
zig build test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-package-distribution -Doptimize=ReleaseSafe -j1
zig build test-runtime-crash -Doptimize=ReleaseSafe -j1
zig build test-platform-host -Doptimize=ReleaseSafe -j1
zig build test-decoder-matrix -Doptimize=ReleaseSafe -j1
zig build test-regex-differential test-regex-fuzz -Doptimize=ReleaseSafe -j1
zig build test-regex-equivalence -Doptimize=ReleaseSafe --fuzz=1M -j1
zig build run-quick-start
zig build run-file-logging
zig build run-structured
zig build run-local-time
zig build run-file-stdout-local-time
zig build run-mmap
zig build run-source-location
zig build run-threaded
zig build run-rolling
zig build run-basic
zig build run-async-memory
zig build run-std-log
zig build run-configuration-sources
zig build bench -Doptimize=ReleaseFast -- --mode=spsc --producers=4 --sink=file --backend=portable
zig build bench-dispatch -Doptimize=ReleaseFast -- --iterations=100000 --repetitions=5
```

`zig build` installs `kroncat` and `kron-bench`; the library is imported through
`dependency.module("kron")`. `verify-local` and `verify` cover single-machine
unit/concurrency/tool tests, negative compilation, real SIGKILL recovery,
independent package consumption, single-threaded executables, regression tools,
and example compilation. Source distribution is verified separately with
`test-package-distribution`. Individual gates include `test-integration`,
`test-crash`, `test-query`, `test-adapter`, and `test-compile-fail`.

```bash
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
zig-out/bin/kroncat --json --where 'request_id == "abc"' app.kron
```

See the [usage guide](../usage.md) for common interfaces; multiple outputs and
rotation also use `Logging`, as shown in
[rolling.zig](../../examples/rolling.zig). `Logging` owns all configured
file/rotating outputs and the underlying Runtime; the caller destroys it once
after all users stop. See [basic.zig](../../examples/basic.zig) for lower-level
extensions; when using `Runtime` directly, it borrows the supplied sink by
default and the Runtime must be stopped/destroyed before the sink. A required
custom sink in journal mode needs an explicit stable `recovery_identity`; file
output provides an absolute-path identity automatically.

In the default multi-threaded build, `flushUntil`, `flushRoutesUntil`, and
`shutdownUntil` accept a monotonic deadline. After a timeout, submitted
operations may still continue and resources remain alive. Single-threaded builds
support synchronous logging and ordinary flush/shutdown; deadline-aware control
returns `TimedControlUnavailable`, and async/SPSC modes return
`ThreadsUnavailable`. See [lifecycle and deadlines](../lifecycle.md).

After explicitly enabling a v2 schema table, scope, format strings, and field
shapes can be pre-registered to reduce repeated metadata capture on the hot path.
Both shared and SPSC loggers support this; see [schema](../schema.md) and
`zig build run-prepared`.

File rotation supports size and monotonic time intervals; trace/span information
can be written to local text, JSON, and archives.

Production capabilities added at this snapshot:

- [Configuration hot replacement](../configuration.md): old events retain their
  original delivery target; resources are released after leases finish.
- [Batch configuration reuse](../batch-configuration.md): background logs from
  the same generation share a protected View; failures retain records and
  resource references.
- [Batch acknowledgement and accounting](../batch-accounting.md): precomputed
  durable route requirements, aggregated written counts for acknowledged
  records, and accurate prefixes on error.
- [Ready-batch coalescing](../coalesced-delivery.md): merge up to 256 ready
  records within the original 64-record service quantum budget, share output
  barriers, and validate/reclaim per record.
- [Schema consumer fusion](../schema.md): with at least 64 ready records, one
  JSON/text/logfmt target, and no template arguments, read validated definitions
  and values directly; short windows and other shapes keep the original path.
- [Route filter performance](../route-filter-performance.md): derive level masks
  at configuration time while preserving scope overrides and old-generation
  decisions.
- [Asynchronous storage selection](../async-storage.md): ordinary Memory async
  and mmap async share an interface with explicit recovery differences.
- [Consumer service budget](../consumer-scheduling.md): bounded polling for
  Memory/Mmap shared and SPSC queues, defaulting to four 64-record service quanta
  and selectable from one to four.
- [SPSC space notification](../consumer-scheduling.md): full-queue producers wait
  on local queue progress while preserving global shutdown/worker-error
  notification and original service order.
- [File reliability](../file-reliability.md): partial writes, rotation, explicit
  durability, and recovery boundaries.
- [Mmap cold publication](../mmap-publication.md): Linux whole-file sync covers
  mapping dirty pages, reducing duplicate publication operations while
  preserving schema readiness and fault boundaries.
- [Nested fields](../structured-values.md): explicit array/group, fixed traversal
  budgets, and recursive redaction.
- [Encoding and archives](../encoding.md): shared paths for full-tree validation,
  length computation, and binary framing.
- [Encoder validation reuse](../encoder-validation.md): complete text/JSON/logfmt
  validates the field tree once while preserving independent value entries,
  formats, and error boundaries.
- [Decimal and escaping output](../decimal-output.md): dedicated decimal output,
  wide-integer chunking, and direct string escaping while preserving formats and
  streaming short-write boundaries.
- [Time handling](../time.md): UTC/fixed offsets, dates and durations, RFC3339
  parsing/output, and same-second caching; no built-in DST database.
- [Field capture](../capture.md): contracts and comparison measurements for static
  named fields, dynamic keys, and context paths.
- [Compressed archives](../compressed-archive.md): standard zlib blocks, with
  `kroncat` read-only inspection and follow.
- [Field and regex filtering](../predicates.md): decisions fixed before
  acceptance, with a fixed-state NFA and no backtracking.
- [Regex matching work](../regex-performance.md): compile-time assertion/epsilon
  expansion, bitmap active states, business-input comparison, and
  coverage-guided fuzz.
- [Global sampling](../sampling.md): exact budgets, configuration-update phases,
  and measured boundaries of dedicated paths.
- [Qualified TSC clock](../tsc-clock.md): explicit selection, hardware/calibration
  checks, and fallback to the native clock.
- [Performance regression](../performance-regression.md): fixed inputs, repeated
  runs, and subprocess affinity; reports inconclusive when noise is too high.
- [Application impact benchmark](../application-benchmark.md): identical
  computation with no logger/Memory/Mmap, independent application-result and
  complete-JSON verification, and CPU/cache/shutdown cost reporting.
- [Submission hotspot optimization](../performance-hotspots.md): native PCLMUL
  CRC, decoded-delivery validation reuse, and fused wire-to-record for a single
  JSON/text/logfmt route; other shapes fall back, with full repeat measurements
  and tail-latency limits retained.

See [local reuse assessment](../local-reuse.md) for local component research and
reuse boundaries. See [platform support](../platforms.md) for implementation,
build, and execution-verification boundaries on
Windows/Linux/macOS/Android/iOS.

## Call path and performance

The historical cross-library comparison used a real Foundation Logging spdlog
frontend plus Rust backend in a 200-trial same-round Memory/Mmap comparison and
20.2 million verified JSON records. Ordinary inline SPSC Memory P1/P4 throughput
medians were 2.342M/2.391M records/s and Mmap 2.322M/2.360M, higher than
Foundation by 8.67%/3.21% and 23.09%/12.58%; all complete through-shutdown
cross-library groups remained inconclusive because variance exceeded the
threshold, and shared Memory P4 was still 4.41% behind. Most schema
configurations were slower, SPSC p99.9 was about 345–347 µs, and Mmap P4
initialization took about 1.25 seconds. Those comparison harnesses and evidence
are no longer tracked; the numbers remain a historical snapshot and do not form a
current ranking.

The normal `scoped()` path retains runtime clock injection.
`loggerWithClock(kron.StandardClock, scope)` statically selects the standard I/O
clock, `loggerWithClock(kron.NativeClock, scope)` uses a vDSO-aware
`clock_gettime` directly on Linux, and `ZeroClock` omits wall-clock timestamps.
SPSC uses `attachThreadWithClock`. Static paths reuse the same field, filter,
journal, and delivery semantics.

`std.Io` is used for explicit application environments, initialization, platform
waits, and the portable backend; mmap reserve/commit does not go through the I/O
vtable, and Linux io_uring is a direct kernel interface. Performance reports
separate frontend quantiles, batch averages, final written drain, and durable
flush; see [benchmark methodology](../benchmark-methodology.md). Small-scale
results are not evidence of being the industry's fastest.

Archived cross-library workflows included spdlog 1.17, Quill 13.1, local
Foundation Logging, and a kron source snapshot, with identical complete JSON and
separate call latency, written flush, shutdown, and startup reporting. Later
native PCLMUL CRC, decoded-delivery validation reuse, fused wire-to-record, and
configuration View/batch accounting each had independent before/after evidence.
A same-round recheck verified 120 trials and 12.12 million records; all groups
were inconclusive because spread exceeded the threshold. Stable rankings still
require a quiet host window.

See [industry implementation and optimization directions](../industry-performance-lessons.md)
for mechanisms confirmed from Quill/Foundation source and fmtlog/NanoLog/
Reckless/BqLog designs, advanced through complete-workflow profiles for
batching, configuration reuse, and CRC work.

Earlier Memory/Mmap-only comparisons and the `4447fe6` workflow snapshot are
historical; their conclusions are not combined into a current ranking. Ready-
batch coalescing against baseline `45f5ec1` completed 240 complete-file trials and
24.24 million verified physical JSON records; portable Memory four-group medians
improved 4.4%–10.0%, three with non-overlapping bootstrap medians; most Mmap
groups remained inconclusive. Independent io_uring P4 Memory improved 14.2%/
23.6% by median, while shared Memory p99 also showed a negative. Complete
ReleaseSafe passed 93/93 steps, 540/540 tests, and nine-target object compilation.

Schema fusion against baseline `366adc3` completed 240 complete-file and 40
complete-PMU trials plus 20 one-million-record P1 rechecks, verifying 56.3 million
physical JSON records. Prepared Memory P4 shared/SPSC throughput medians improved
6.35%/8.03% with repeatability and non-overlapping medians; schema user
instructions fell about 1.8%–1.9%. Most Mmap groups and call tails remained
inconclusive, and P1 long-workflow Memory/Mmap negative medians of 0.65%/1.39%
overlapped; all original slow values were retained. Complete ReleaseSafe passed
93/93 steps, 545/545 tests, and nine-target compilation.

Shared admission later held the validated configuration View directly until
`end` released the reader, while accepted records kept an independent pin.
Formal 370 complete-file/PMU/one-million-record rechecks verified 54.37 million
JSON records; shared schema Mmap single-producer long-workflow median improved
4.79% with repeatability and non-overlapping intervals. Other paths did not
qualify for a general gain, and a PMU shared Memory four-producer negative median
of 3.36% was retained.

SPSC full-queue waiting now waits on the local queue's in-process space epoch,
avoiding repeated waits triggered by other queues' progress; original queue
service order, CRC/configuration references, and acknowledgement boundaries are
preserved. Formal 400 complete-file/PMU/one-million-record comparisons verified
84.40 million JSON records; Memory inline SPSC four-producer long sampled p99.9
median moved from 366.312 to 340.708 µs (−6.99%) with repeatability and
non-overlapping medians; ordinary throughput, p50/p99, and most Mmap tails did not
qualify. Each Journal object gained 64 bytes, while queue/file budgets and
allocation counts did not increase.

Prepared optimization passed 556 complete ReleaseSafe tests and nine-target object
compilation. Prepared submission measured dynamic value/nested-key bytes during
the original full-tree validation and reused them only within the same unchanged
call; the public reference codec, canonical/ready references, CRC/pins/barriers
continued to validate. 380 complete-file/PMU/one-million-record comparisons
verified 64.38 million JSON records; schema user instructions fell about 4%, and
shared Memory single-producer long batch throughput median improved 4.89% with
repeatability and non-overlapping intervals. P1 long sampled p99.9 was negative,
and most P4/Mmap groups did not qualify.

## Implementation order

1. Fix event, field, configuration, and reliability contracts; establish the Zig
   0.16 build skeleton.
2. Implement synchronous text/JSON, filtering, context, redaction, and a basic
   file sink.
3. Implement the self-contained journal format, commit protocol, recovery tools,
   and crash-injection tests.
4. Implement journal-based async background delivery, flush, checkpoint, and
   shutdown.
5. Add per-thread SPSC, deferred-formatting optimizations, and dynamic
   configuration caches.
6. Implement the Linux io_uring backend, rotation, and fair performance
   benchmarks.
7. Add optional binary archives, flight recorder, and ecosystem adapters.

See [overall design](../design.md) for each stage's acceptance criteria,
unpromised capabilities, and risk boundaries.
