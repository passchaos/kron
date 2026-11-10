# Ordinary asynchronous and mmap asynchronous storage

Both modes capture self-contained events on the producer thread and perform
filtered delivery, formatting, and output in the background. The choice affects
only queue storage and recovery contracts:

| Mode | Option | Submission storage | Queue records after a process crash |
| --- | --- | --- | --- |
| Ordinary async | `memory_queue` | Fixed memory preallocated by the caller's allocator | Undelivered records are lost |
| mmap async | `journal` | File-backed shared writable mapping | Complete committed records recover, with replay allowed |

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .asynchronous,
    .memory_queue = .{ .capacity = 256, .max_record_bytes = 8192 },
    .routes = &.{.{ .name = "file", .sink = file.sink(), .format = .json }},
});
```

Replace `memory_queue` with
`journal = .{ .path = "app.journal", .capacity = 256, .max_record_bytes = 8192 }`
to select mmap. The options are mutually exclusive; the library never
automatically downgrades to Memory when mmap fails and silently changes recovery
guarantees. Asynchronous initialization without a selected storage returns
`JournalRequired`; synchronous mode does not accept asynchronous storage
configuration.

Ordinary async has no journal file, file lock, file preallocation, file mapping,
or initialization file sync; fixed space comes from the caller's allocator, and
capture, reserve, commit, and drain do not allocate after initialization. The
allocator itself may use system anonymous-memory mechanisms. It reuses the same
bounded slot/sequence/commit protocol and codec, preserving typed fields, nested
snapshots, Secret, dynamic configuration, sampling, and redaction. The memory
data structure keeps a fixed protocol header for unified state management but does
not represent an on-disk archive or recovery.

Both modes support shared producers and explicitly registered SPSC:
`.submission = .low_latency` with `max_thread_channels`, and each channel is
preallocated at initialization using the selected storage. Memory mode does not
require a required custom sink to have a cross-restart identity; mmap mode still
does. `max_journal_bytes` is now the total budget cap for all queue storage,
including shared queues and channels; the name is retained for API compatibility.

Ordinary multi-producer programs can use the shared queue and do not need thread
logger registration. An experiment that allocated thread counters and
configuration caches by budget reduced ordinary Runtime requests by 15 KiB, but
two P1 batch throughput rounds showed negative medians and the main-path cost was
not ruled out, so the candidate was withdrawn. Runtime keeps its original fixed
state layout; future resource optimization must also pass shared performance
comparison.

See [mmap.zig](../examples/mmap.zig) for a complete unified-entry Mmap example,
run with `zig build run-mmap -Doptimize=ReleaseSafe`. Logging uses
`.mode = .asynchronous` and `.queue = .{ .mmap = options }`, manages a required
JSON file and best_effort stdout, formats system local time in the consumer, and
explicitly confirms durable and shuts down. Reopen uses the same path, layout, and
recovery target identity.

`runtime.queueStorage()`/`health().queue_storage` return none, memory, or mmap.
`queue_reserved_bytes` reports total queue space; `journal_reserved_bytes`
reports only file-mapping space and is zero for ordinary async.

## Acknowledgement and reliability

Ordinary async accepted means the event entered fixed memory queue; abnormal
process exit loses records still in the queue. Written still waits for all
required outputs to be completely written. `flush(.durable)` first drains prior
logs and synchronizes output files that support durability, but does not treat the
Memory queue as a recoverable journal or create a Memory durable checkpoint. New
undrained events still cannot survive a process crash.

Direct Memory queue `Journal.sync()` returns `UnsupportedDurability`; a Memory
configuration with `reclaim_after = .durable` returns
`DurableReclaimRequiresMmap`, and the submission queue cannot claim persistent
reclamation. `recovery_versions` applies only to mmap; Memory mode returns
`RecoveryRequiresMmap`. A Memory schema table can be used for in-process
pre-registration and capture optimization, but schema-ready does not imply
cross-process persistence.

mmap accepted/written/durable boundaries follow the original protocol; see
[lifecycle](lifecycle.md) and [platform support](platforms.md). Both modes use a
bounded queue and follow block/drop_newest/fallback_sync policies when full.
Ordinary mode can be seen with `zig build run-async-memory`.

A slow-sink diagnostic (200 µs/record, 64 slots, 1000 events) shows the policy
trade-off: block loses nothing but P1/P4 emit p99 is about 15–16 ms and P16 about
59–81 ms; drop_newest keeps p99 sub-microsecond but retains only the 64 records
the consumer can handle (P16 keeps only 65/1600); fallback_sync loses nothing but
synchronously writes slowly on a full queue, with p50 about 0.24 ms and P16 p99
about 59 ms. Applications must choose by acceptable blocking tail or record loss,
not only steady-state throughput.

`MemoryQueueOptions.verify_crc` defaults to `true`. Setting it to `false` is an
opt-out for **volatile Memory queues only**: the producer does not write slot CRC
and the consumer does not verify it; mmap/recoverable journals reject this
configuration. Five E-core production-build diagnostics showed Memory P1/P4
throughput about +20.0%/+23.1%, but this is only for applications that accept
undetected memory corruption or partial payloads and is not recommended in
untrusted or corruption-prone environments.

## Verification

`test-async-storage` covers both frontends' Memory queues, an I/O trap that
forbids file open/create, source-overwrite snapshots, hot configuration/
redaction, zero allocation after initialization, full-queue drops, shutdown
waking blocked producers, schema pre-registration, and output file durability.
`test-async-crash` uses real child-process SIGKILL: three accepted/unwritten
records are lost in Memory mode and all recover in mmap mode; three previously
written output records survive in both modes, and a normal drain is also
accepted=written.

```sh
zig build test-async-storage -Doptimize=ReleaseSafe -j1
zig build test-async-crash -j1
zig build bench-snapshot -Doptimize=ReleaseFast -- --mode=attached --phase=full --producers=4 --events=10000 --storage=memory
```

Benchmark results always label `queue_storage` and `process_crash_recovery`. The
two modes have different reliability and are never compared as "same-semantics
optimization"; repeated-trial reports are no longer tracked. Current runs include
ten complete-delivery trials per mode, each confirming 100,000 written records
with pending/drop/measurement allocation all zero. Small-scale measurements are
not a stable ranking.
