# Journal v1

`journal.zig` owns a bounded, fixed-slot file mapping. `Journal.create` takes
`std.Io`, a path, slot capacity and maximum payload size. Little-endian 64-bit
Linux, Windows, macOS, Android and iOS targets have native file-mapping backends.
The exact compile/runtime evidence is in [platforms.md](platforms.md).
Linux/Android reserve disk space with fallocate; Windows uses allocation-size
metadata and file mapping; Darwin uses F_PREALLOCATE and MAP_SHARED. Known
volatile filesystems or unsupported preallocation return explicit errors.
Initialization locks the file exclusively, prefaults writable pages and publishes
the initial file/header. Strict durable sync is a separate platform capability;
Windows currently cannot confirm directory-entry durability. An unrelated process
must never truncate an active journal.

The journal accepts opaque, self-contained bytes. The event codec must include
all schema/metadata required to decode them in a new process. No pointer, slice
or native Zig struct layout is written to the protocol.

The 4096-byte header precedes `capacity` slots. Slot stride is
`alignForward(64 + max_record_bytes, 64)`; total mapped bytes are
`4096 + capacity * stride`. All integers are explicitly little-endian. The
immutable header has magic, format version, endian marker, capacity, payload
limit, stride, a persistent random 128-bit session identity and CRC32. Mapped
atomic reservation/written cursors live outside the immutable CRC. Two
alternating CRC-protected epoch/sequence checkpoints record durable reclaim.

| Slot offset | Field |
| --- | --- |
| 0 | Aligned atomic u64: sequence shifted left by 2, plus state |
| 8 | u64 sequence, beginning at 1 |
| 16 | u64 generation: `(sequence - 1) / capacity + 1` |
| 24 | u32 payload length |
| 28 | CRC32 of sequence, generation, length and payload |
| 64 | Payload bytes, bounded by the configured maximum |

State 0 is free; 1 is reserved, 2 committed and 3 aborted. Release publishing
of a committed tag follows payload/header/checksum writes. Consumer acquire
loads precede reads. In-memory slot turns also protect a producer paused after
claiming its sequence but before writing any slot metadata. They are rebuilt
from validated slots during recovery, never trusted as persisted state.

One consumer owns all peek/release operations. Multiple producers may reserve
and commit concurrently. A live reservation gap blocks later records; abort
publishes a tombstone. Opening a journal scans every independently located
slot, validates committed records and sorts them by sequence. It abandons
incomplete reservations and can therefore recover later committed events
across a gap. Recovery errors retain the file as evidence. `recover=false`
returns `RecoveryRequired` if pending valid records exist.

`peekBatchChecked` borrows a consecutive checked batch without reclaiming it.
It consumes leading tombstones and stops at internal tombstones/reservations
or at the recovered/live boundary. The collector must flush every required
output before releasing borrowed records in sequence. The unchecked peek
methods assume memory has not been corrupted; collector code should use the
checked methods. A `Reservation` or `Record` is a borrowed handle with exactly
one owner; it must not outlive the journal, be copied for concurrent use, or be
used after its commit/abort/release.

`release` acknowledges written output and returns a slot for reuse without a
syscall. The caller must already have completed all required output writes.
An output write followed by a crash before journal release may replay the
event: recovery is at least once. Written release protects against a process
crash while the OS remains running, and does not promise power-loss recovery.

The shared written cursor uses a release atomic maximum. An acquire
`writtenTarget()` read that observes newly advanced progress also observes the
consumer's preceding writes. Slot-turn publication and Runtime pin/count cleanup
can follow that cursor update; complete lifecycle confirmation still uses the
Runtime's flush and shutdown protocol. This does not extend a released Record's
borrowed payload lifetime or make peek/release safe for multiple consumers.

`releaseAfter(record, .durable)` requires all required outputs to have been
synced by the caller. It syncs commit data, alternates and syncs the durable
checkpoint, then persists slot invalidation before enabling reuse. A failed
sync retains consumer ownership for retry. `sync()` only syncs the journal;
it does not sync sinks or advance output durability. Deinitialization closes
the mapping/lock and deliberately performs no implicit sync or acknowledgement.
System-crash and power-loss claims require filesystem/storage fault-injection
qualification beyond these process-reopen tests.

`pending`/`count` include occupied reservations, commits and tombstones;
`highWater` is the peak occupied count. `reservationTarget` is the greatest
allocated sequence, while `writtenTarget` includes passed tombstones and
released records. `durableReclaimedTarget` is the persisted reclaim checkpoint.
These counters and producer methods use atomics; head/recovery iteration remain
consumer-owned. Producers, consumer and sync callers must stop before deinit.
