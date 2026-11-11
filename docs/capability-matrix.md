# Capability matrix

This page combines the common mode, storage, format, and recovery/durable
boundaries in one table so rules do not have to be assembled from several topic
documents. Defaults follow the `Route` fields; every opt-in fast path leaves the
default durable/CRC/recovery/queue contracts unchanged.

## Runtime modes and storage

| Mode / storage | Process-crash recovery | Durable | Suitable scenario | Main constraint |
| --- | --- | --- | --- | --- |
| sync | none | Output synchronization may be requested after the calling thread finishes | Small tools, single-threaded, low-frequency logging | No background queue; timed/async control interfaces return capability errors |
| shared Memory | none; pending records lost | Outputs may be durable; the queue itself does not recover | Ordinary background logging | Bounded shared queue; undelivered records are lost on crash |
| shared Mmap | Complete commits recovered, at-least-once replay | Journal checkpoint + output synchronization | Process-crash recovery required | Requires a preallocatable, non-volatile filesystem |
| SPSC Memory | none; pending records lost | Outputs may be durable; the queue itself does not recover | Fixed threads with verified benefit | Explicit attach/detach; per-thread preallocated queues |
| SPSC Mmap | Complete commits recovered, at-least-once replay | Journal checkpoint + output synchronization | Fixed threads + crash recovery | Explicit attach/detach; exclusive recovery |
| `MmapSpool` | no journal recovery | **non-durable** | Highest P1 mmap throughput where no recovery is acceptable | No journal/CRC/recovery/ring/consumer; one producer per spool, or one spool/channel per producer |

## Formats and output

| Format | Output | Notes |
| --- | --- | --- |
| text | Human-readable lines | Default format; source locations print as `path:line:column` |
| json | Complete JSON Lines | Supports inline/schema, render cache, and the text fast path |
| logfmt | key=value lines | Shares field capture and filtering with text/json |
| binary | Self-contained journal/archive frame | `kroncat` supports read-only queries, follow, and recovery |

File output uses the portable backend by default; Linux `io_uring` is explicit
opt-in. Rotation supports size, a time interval, or either trigger; archives use
standard zlib.

## Opt-in fast paths

| Option | Gain direction | Recovery/CRC | Combination constraints |
| --- | --- | --- | --- |
| `MemoryQueueOptions.verify_crc=false` | Skips Memory slot CRC | Volatile Memory only; default CRC remains | Rejected for mmap/recoverable journals; only for applications that accept undetected memory corruption |
| `text_format` | Producer renders final JSON; consumer writes it directly | No journal recovery; requires `verify_crc=false` | Single JSON route, async/SPSC, Memory or `recover=false` mmap; cannot be combined with render cache |
| `render_cache` | Producer renders into a volatile cache; consumer writes hits directly | Journal/CRC/recovery retained; the cache itself is volatile | Requires a journal; supports shared async/SPSC single-route JSON inline/schema; off by default |
| `MmapSpool` | Producer renders directly into a file-backed mapping | No journal/CRC/recovery | Non-durable; one producer per spool, or one spool/channel per producer; optional coarse timestamp |

## Completion boundaries

- `flush()` confirms required outputs written.
- `flushDurable()` requests the durable protocol for applicable outputs and
  journals; not applicable to `MmapSpool`.
- `shutdown()` closes admission and drains; `destroy()` is blocking cleanup and
  requires all users to have stopped.
- An Mmap commit is not a power-loss guarantee; process-crash recovery is
  at-least-once replay, not exactly-once.
- Physical power loss, non-Linux devices, NFS/CIFS/FUSE, and broader filesystems
  still require independent qualification.

## Failure capture

| Mechanism | Trigger | Output | Boundary |
| --- | --- | --- | --- |
| `FailureHandler.record` | Explicit application call | One crash file plus stderr mirror; no termination | Returns `error.CrashFileUnavailable` when the file cannot be created |
| `FailureHandler.fatal` | Explicit call or bound `.fatal` event | One crash file plus stderr mirror, then `SIGABRT` | `.fatal` binding requires `abort_on_fatal`; filtered/sampled events never reach dispatch |
| Signal handlers | `SIGSEGV`/`SIGILL`/`SIGFPE`/`SIGABRT`/`SIGBUS`/`SIGTERM` | Crash file with signal/code/fault address and raw stack addresses, then re-raise | POSIX only; signal symbolization is opt-in; alternate stacks are per-thread |

Crash files are diagnostic and do not drain queues, flush outputs, or replace
journal recovery. See [failure handler](failure-handler.md).

## Platforms

Linux has real execution qualification. Windows/macOS/Android/iOS have
implementations and cross-compilation or partial-link evidence, but still need
target-device execution qualification. aarch64-linux-musl runs the root suite and
fuzz under QEMU user mode. See [platform support](platforms.md) and
[current acceptance status](implementation-status.md) for detailed boundaries.
