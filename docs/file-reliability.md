# File writes, rotation, and recovery boundaries

`FileSink` accepts bytes as complete records, and the portable backend handles
short writes with explicit offsets. Each successful segment advances the actual
offset; zero progress returns `WriteZero`, and a full disk returns `NoSpaceLeft`.
An error after a partial write is latched, so later write/flush/shutdown calls do
not blindly repeat the written prefix. A Runtime required route that hits an
error preserves the complete journal record, stops background delivery, and
returns the error; best_effort failures are counted without blocking other
required target confirmations.

Six external fault tests use real files and mmap journals: the successful prefix
is actually on disk, and offsets, health counters, latched errors, commit marks,
CRC, and pending sequence numbers are verified. After all owners stop, the
application explicitly recreates output and starts a new Runtime to replay
complete records; the library never automatically truncates or repairs corrupt
output. The journal preserves replayable events, and a partial output is never
treated as confirmed completion.

## Ordinary rotation and durability

Size/time rotation waits only for the old file's user-space buffers and in-flight
I/O, then renames the archive and opens a new active file. Ordinary written does
not implicitly request fsync or F_FULLFSYNC, so ordinary logging does not stop
permanently merely because the filesystem lacks strict durability.

Explicit `RollingFileSink.sync()` performs: current file-data strict sync →
each still-retained known archive strict sync → parent-directory strict sync. At
startup it records existing regular archives and updates a fixed existence table
after successful rotation; unused retention slots may be empty, while a missing
tracked archive returns an error instead of false durable success. Only one
archive descriptor is open at a time, and sync does not allocate heap memory.

The `path` and `path.N` file set is owned exclusively by the sink; other
processes must not modify, replace, or delete controlled archives. Retention is an
explicit data-expiration policy; the durable guarantee covers only files still
retained, not old logs already deleted by retention. Multiple rotation renames are
not a single transaction over the file set; an I/O failure latches and preserves
the current state without guessing how to recover moved names.

`FileSink.syncData()` confirms only file data; `sync()` also requires the parent
directory protocol. When a platform reports `UnsupportedDurability`, ordinary
written capability is not broken, while real `InputOutput`/`NoSpaceLeft` errors
continue to latch. See [platforms.md](platforms.md) for actual Windows/Apple
capability boundaries; the existence of a protocol is not device power-loss
qualification.

After a retired configuration has no record pins and completes its required
written barrier, it attempts any applicable extra durable finish. If static sink
capability differs from actual capability and returns `UnsupportedDurability`, the
configuration may still be reclaimed while global historical durable
qualification is permanently withdrawn; real I/O errors retain the generation and
lease for retry. This keeps optional finishing work from permanently occupying a
configuration slot and does not assume old output is durable.

## External reopen

Calling `reopen()` after an external rename drains the old file, attempts strict
file-data sync, then opens a new active file. It does not receive the external
target directory, so after closing the old descriptor it cannot confirm
persistence of the external directory entry; a successful reopen therefore
permanently removes that sink instance's historical durable qualification.
Ordinary write/flush continues to work, and sync returns `UnsupportedDurability`.
Even if the borrowed Sink's static capability field is true, live sync checks this
state.

If the application requires external archives to be durable, it must explicitly
synchronize their target files and directories and own their lifetime. The current
interface does not infer external destinations or claim that old file-data sync
covered the external directory.

## Fault and recovery acceptance

```sh
zig build test-file-delivery -Doptimize=ReleaseSafe -j1
zig build test-recovery-campaign -j1
zig build test-runtime-crash -Doptimize=ReleaseSafe -j1
```

Rotation-targeted tests cover rotation when strict sync is unsupported but
written remains available, absence of implicit sync, archive sync order, tracked
missing archives, reopen qualification, I/O error latching, and OOM cleanup. The
seeded recovery campaign uses a 16-slot journal with random written counts 64–127,
pending counts 1–7, and configuration switch positions, distinguishing
self-contained and pre-registered schemas; after confirming cross-generation
pending records, it force-kills the process and checks the written prefix,
recovered suffix, source/nested/secret data, CRC, and repeated inspection without
file modification.

The campaign randomizes workload and epoch boundaries and kills at an exact READY
point; it is not arbitrary-time fault sampling or physical power loss. Child-QEMU
system-shutdown evidence and platform device qualification are reported
separately.

## Random termination during normal operation

`test-runtime-crash` uses two real producers, shared MPSC and independent SPSC,
each covering self-contained payloads and pre-registered schemas. Each producer
first submits 64 records and waits for the coordinator to confirm the written
prefix, then continues submitting variable-length strings, nested fields, bytes,
and sensitive values. After READY, the driver SIGKILLs the child at a seed-derived
8–75 ms time; submit and background write threads are still running, with no fixed
reservation/commit stopping point. This test includes acknowledgement pipelines
and deliberate load intervals and is not used for performance measurement.

The producer sends an ACK only after each public emit returns accepted, then
starts the next call. An independent Python oracle requires every complete ACK to
appear in complete JSON output or in an independent `kroncat` recovery result;
there is still an observation window between the call return and the ACK, so each
producer may have at most the next unacknowledged complete event. The test cannot
know the return state of a call that had not been acknowledged at the kill
instant. It also verifies the warm prefix was written, per-channel sequence
increase, stable event identity, data snapshots, recursive redaction, and
Python-zlib-independent header/slot CRC plus the complete commit set.

Written and recovered sets may overlap, but the same event identity must have the
same payload; duplicates or identity conflicts within one result fail. If the
output ends with an incomplete record, it must be a byte prefix of some complete
recovered record; a corrupt tail is never treated as a successful log. Two
independent inspections must produce exactly identical output, and the journal and
original output hashes must remain unchanged. Raw files stay in a temporary
directory until checking finishes; tools do not repair or consume them.

Thirty-two ReleaseSafe ordinary seeds and eight u64-boundary seeds passed,
covering 109,419 complete ACKs, 69 recovered records, four output/recovery
overlaps, and 11 observed incomplete reservations. Writer, reader, and library
module used the same optimization level from the project build; formal
ReleaseSafe/ReleaseFast gates passed 12 scenarios each. That round did not observe
a partial output tail; the existence of tail validation does not mean the random
campaign hit that branch, and real short-write qualification still comes from the
file-fault tests above. Six negative oracle tests confirm that omissions, snapshot
corruption, duplicates, identity conflicts, ACK gaps, and CRC corruption are
rejected.

Random timing samples process crashes only on the tested workload and host; it
does not exhaust every instruction boundary and does not prove system shutdown,
other filesystems, device power loss, or non-Linux platform qualification. Seeds
fix the workload and request delay; actual process scheduling and termination
location can still vary, and reports record requested versus actual delays.

After the 2026-11-01 reference-encoding optimization, the complete ReleaseFast
gate reran the random campaign; seed 20261036 in shared/schema mode hit a
1,950-byte incomplete JSON tail. The test confirmed this byte range was a prefix
of a complete independently recovered record, and all ACKs remained covered by
complete output/recovery. This is an actual runtime partial-write hit for the
current source; logs and source identity were retained in that round's evidence.
The earlier 52-scenario JSON report keeps its original record and is not rewritten
to claim this branch was hit.
