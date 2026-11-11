# Current implementation and acceptance status

This page records current capabilities, recent gates, and unfinished scope. See
[design.md](design.md) for design goals, [usage.md](usage.md) for the application
entry point, and the [historical acceptance snapshot](history/implementation-before-reorganization.md)
for earlier implementation and performance records. Historical counts and test
results are bound to their source revision and do not automatically apply to a
later HEAD.

## Current scope

Single-machine logging on Windows/Linux/macOS/Android/iOS with Zig 0.16,
covering synchronous and shared/SPSC Memory/Mmap, text/JSON/logfmt/binary,
structured fields, configuration, sampling/redaction, files/rotation/archives,
`std.log`, and explicit trace correlation. Network sinks/exporters have been
removed. Linux has real execution qualification; other platforms are tracked
separately.

`Logging` is the unified application owner. It manages independent route
pipelines, rotation, stable writer storage, and each route's Runtime through the
`outputs` list. Ordinary integration does not need a second resource owner; the
lower-level Runtime remains for advanced extensions and existing APIs.

`Logging.Options` keeps the `outputs` list, the total queue budget, and an
optional failure handler, with defaults defined directly on route fields. Each
route has independent mode/queue/overflow/redaction/sampling and state. Rotation
supports size, a pure time interval, or either trigger, with time rotation
checked at record boundaries.

`FailureHandler` is an independent, opt-in process failure reporter. It writes
glog-style crash files with raw stack addresses for fatal signals, mirrors them
to stderr, and can turn a delivered `.fatal` event into a terminating report. It
does not drain the logging runtime and is not a durability or power-loss
mechanism; see [failure handler](failure-handler.md).

## Recent verification

As of 2026-11-11, the repository's correctness gates cover the root unit and
integration suites, compile-fail checks, fuzz/decoder corpora, single-threaded
builds, real SIGKILL recovery, async crash recovery, the recovery campaign,
real fatal-signal/fatal-event crash capture, and cross-platform compile checks.
The exact pass counts are produced by the commands in
[development and verification](development.md); they are not duplicated here
because they change with every test addition.

The cross-library C++/Rust reference harnesses and their measured evidence have
been removed from the repository. Current performance work uses the in-repo Zig
benchmark suite (`bench/`) and its report self-tests. Durable memory remains the
recommended default; `text_format`, `MmapSpool`, and `render_cache` are opt-in
fast paths, and the default durable/CRC/recovery/queue contracts are unchanged.

Per-candidate measurements, gate counts, source identities, and positive or
negative results belong in the
[verification chronology](history/verification-chronology-2026-11-09.md). Add
new verification records there; this page only tracks current conclusions,
capability tables, and priorities.

## Capabilities and verification entry points

| Capability | Existing verification and documentation | Qualification boundary |
| --- | --- | --- |
| Zig package and application owner | Independent `b.dependency`, five modes, source distribution, single-threaded; [package](package.md), [guide](usage.md) | Version pinned to 0.1.0; later changes require re-verification |
| Typed fields/context | Scalars, optionals, nested values, explicit object adapters, borrowed/owned, Secret; [fields](capture.md), [nesting](structured-values.md) | Explicit containers and fixed node/depth budgets |
| Encoding and archives | Four outputs, framing, legacy/current decode, short buffers/mutation, read-only Reader; [encoding](encoding.md), [compression](compressed-archive.md) | Journal/schema/event/archive versions are independent |
| Dynamic configuration and policy | Source transactions, scope filters, configuration generations/leases, old-record targets; [configuration](configuration.md), [predicates](predicates.md), [sampling](sampling.md) | Full replacement and filter-only updates differ in phase/ownership |
| Bounded Memory/Mmap | Shared/SPSC, full-queue policies, snapshots, allocation-free paths, schemas; [storage](async-storage.md), [schema](schema.md) | Memory does not recover pending records; Mmap allows at-least-once replay |
| Threads and lifecycle | Thread token/generation, admission cut, deadlines, shutdown/failure wakeups; [lifecycle](lifecycle.md), [scheduling](consumer-scheduling.md) | Timeout does not cancel background work; destroy is blocking cleanup |
| Files, rotation, and io_uring | Short writes, CQE/in-flight ownership, size/time/retention/reopen, real synchronization; portable default, io_uring explicit; [files](file-reliability.md) | Backend implementation, device capability, and power-loss qualification are separate |
| Process recovery | Real SIGKILL across committed/reserved/gap/schema/hot-route cases and random ACKs | Process-crash tests do not replace system power-loss tests |
| Failure capture | Real SIGSEGV/SIGABRT/SIGTERM and fatal-event children; crash-file naming/content, raw stack addresses, symlink, stderr mirror; [failure handler](failure-handler.md) | POSIX signal handlers only; symbolization is best-effort; alternate stacks are per-thread; crash files are not durable evidence |
| Durability | Output/checkpoint ordering, fault sinks, child-QEMU shutdown recovery (ext4/XFS/Btrfs/F2FS 16-run campaigns); [power tests](../tests/power_loss/README.md) | Physical power loss, NFS, and devices still need broader qualification |
| Time, std.log, trace | RFC3339/fixed offsets, independent oracle, Bridge, explicit TraceContext; [time](time.md), [API](api-design.md) | Fixed offsets stay pure Zig; local time uses system DST rules; no bundled IANA database or full tracing task/span ecosystem |
| Platforms and single-threaded | Nine-target object/partial-link checks; Linux real files/recovery and one OS thread; [platforms](platforms.md) | Windows/macOS/Android/iOS still lack device execution |
| Performance and application impact | Complete files, user-space PMU, application result oracle; [benchmark navigation](../bench/README.md) | Many complete throughput/tail groups remain inconclusive; no universal fastest guarantee |

## Priority of remaining work

| Priority | Gap | Follow-up acceptance |
| --- | --- | --- |
| 1 | Reproducible end-to-end performance baseline | Establish low-noise same-workload baselines for shared/SPSC, Memory/Mmap, P1/P4, and batch/sampled on P-core and E-core; judge init/warmup/producer/written/shutdown/cleanup and p99/p99.9 independently; require complete pairing and noise thresholds, and do not combine historical percentages |
| 1 | Tail latency and overload impact on applications | A synthetic 200 µs slow-sink/64-slot diagnostic is recorded: block P1/P4 p99 around 15–16 ms with no loss, P16 p99 around 59–81 ms; drop p99 is sub-microsecond but drops 936/1000 or 1535/1600; fallback p50 is around 0.24 ms. Burst, backlog age, CPU/cache/scheduling contention, and a no-logger baseline are still needed |
| 1 | Mmap startup and resource cost | Fresh Linux mmap initialization that writes only the header reduced a 16.8 MB journal init median from 54.2/53.8 ms to 8.2/6.9 ms; broader filesystems/devices, dirty-page behavior, and durability boundaries still need verification |
| 2 | Broader business/durable regression coverage | 0/5/10 fields, short/long strings, P1/P4/P16, warm/cold, attach/detach, reload/rolling, and independent durable measurements |
| 2 | Broader faults, upgrades, and sustained fuzz | Journal/archive, regex/predicate, and decoder fuzz include runner-seed scans (1000/1000/1000 seeds); v1/v2 upgrade compatibility, pre-V3 old-binary v1/v2 fixtures, nested prepared+rolling+schema journal+reopen combinations, the V3 child-VM abrupt-loss campaign, and XFS/Btrfs/F2FS child-VM campaigns are in regression; concurrent soak has 1000/200 repetitions; tmpfs/ext4 and 9p shared-FS behavior are compared; real ENOSPC FileSink/Journal preallocation errors and read-only FS initialization rejection are covered. Still missing: Windows/macOS/Android/iOS old-binary/earlier-format fixtures, NFS/CIFS/FUSE/device system shutdown, physical power loss, and sanitizers (Zig TSan is not instrumented and Helgrind is incompatible with Zig atomics), plus longer soak runs |
| 2 | Non-Linux platform execution | aarch64-linux-musl runs the root suite and fuzz under QEMU user mode; Windows/macOS/Android/iOS still lack target-device logging, lifecycle, journal recovery, and durability reports |

The main functionality has verification. The complete "industry best" goal is
still in progress. Future status updates record only actual source revisions,
run results, or explicit platform capability rejections.
