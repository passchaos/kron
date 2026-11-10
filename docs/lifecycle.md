# Flush, deadlines, and shutdown

A multi-threaded `Runtime` owns the journal, background delivery thread,
preallocated control slots, and control thread; the supplied sink is still owned
by the application. After stopping all logger/token users, the application
destroys the Runtime first, then the sink. This document's background thread
consumes a local journal.

An ordinary asynchronous `memory_queue` uses the same background delivery and
admission cut, but storage is memory provided by the caller's allocator.
`flush(.durable)` can confirm output files that support a durability protocol; it
does not persist the Memory queue or create a checkpoint for it. Undelivered
Memory records are lost on process crash. See
[asynchronous storage selection](async-storage.md).

`single_threaded=true` builds support synchronous mode and do not allocate control
objects or create threads during initialization. `flush`, `flushRoutes`, file
durable synchronization, configuration reload, and `shutdown(.drain)` work
normally. Async/SPSC initialization returns `ThreadsUnavailable` before allocating
or creating a journal; `flushUntil`, `flushRoutesUntil`, and `shutdownUntil`
return `TimedControlUnavailable` without publishing an operation or closing
admission early. `controlStatus().available=false`, and its counters are zero.
Single-threaded applications call ordinary blocking interfaces directly and own
their external time budget.

## Completion boundaries

- `flush(.drain)` waits for target events to be processed by the background
  delivery thread.
- `flush(.written)` waits for target outputs to be completely written, flushing
  user-space writers and in-flight I/O.
- `flush(.durable)` additionally performs durability synchronization for required
  sinks and journal checkpoints; a required route that does not support durable
  returns `UnsupportedDurability`.

`flushRoutes(names, boundary)` confirms only explicitly selected routes. A durable
flush for a subset does not declare the whole journal watermark durable.

An ordinary flush establishes an admission cut that includes calls already
capturing but not yet reserved; new events after the cut are not covered by that
guarantee. SPSC establishes the same cut over a fixed channel set. The
implementation never infers completion from "the queue is momentarily empty".

## Deadline-aware interfaces

```zig
const deadline = kron.Deadline.after(io, 50 * std.time.ns_per_ms);
try runtime.flushUntil(.written, deadline);
try runtime.flushRoutesUntil(&.{"file"}, .durable, deadline);
try runtime.shutdownUntil(deadline);
```

Each call uses one absolute deadline, and `Deadline.after` selects the awake
monotonic clock. `Deadline.fromTimestamp` accepts only awake/boot values and
rejects real wall clocks that can jump.

The deadline covers waiting for existing control operations, the admission cut,
background delivery progress, sink flush, and sync. Control slots and threads are
preallocated during Runtime initialization; the caller does not lend a stack
request object to the background.

**`Timeout` means the caller stopped waiting; it does not mean I/O was cancelled.**
A published operation continues on its owning control thread. Buffers, journals,
sinks, and the Runtime must remain alive until the operation completes.
`runtime.controlStatus()` exposes busy/detached counts, completion/timeout counts,
and the most recent control error.

The caller may retry later: a new request waits for the previous operation to
complete, and that wait also counts against the new deadline. One slot keeps
control resources bounded. If the deadline has already expired before submission,
no new operation starts.

`shutdownUntil` closes admission on all channels before waiting, then publishes
the background delivery thread's global shutdown point; a non-expired call keeps
admission closed even if it times out. An unfinished final sink barrier
corresponds to `closing`; after the final barrier succeeds or fails, the state
becomes `closed`. Repeated shutdown returns the latched shutdown result.

## Resource management after a timeout

The application must not release the sink, journal, or Runtime immediately after
a `Timeout`. `destroy()` waits for published control operations and the background
delivery thread to finish; it is a blocking cleanup interface and provides no
bounded-time promise. Unrecoverable underlying I/O may still make it wait.

Calling destroy from log submission, the background delivery thread, the control
thread, or a diagnostic hook is forbidden. Reentrant flush/shutdown returns an
explicit error; violating destroy's lifetime preconditions fails directly to avoid
releasing an object still in use.

## Verification

```bash
zig build test-deadline -j1
zig build test-deadline -Doptimize=ReleaseSafe -j1
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
```

External tests use entered/release event handshakes to block real sink callbacks
and verify timed flush/sync, shutdown `closing` state, no start after an expired
deadline, waiting while a control slot is occupied, retry after failure, producer/
worker/control/hook reentrancy, and zero allocator calls after initialization.
They verify caller timeout and resource ownership; they cannot be described as
guaranteeing that hardware I/O finishes within a deadline.
