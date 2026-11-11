# Failure handler and crash capture

`kron.FailureHandler` is an optional, glog-style process failure reporter. It
installs handlers for fatal signals, writes a crash file with raw stack return
addresses, mirrors the report to standard error, and maintains a stable
`<program>.FATAL` link. It can also bind to `Logging` so a `.fatal` event
terminates the process after delivery.

The failure handler is independent of the journal and sinks. It does not drain
queues, flush outputs, or claim durability; its crash file is diagnostic
evidence, not a replacement for [journal recovery](journal-protocol.md) or the
[completion boundaries](lifecycle.md).

## Installation

The handler owns fixed storage, so place it in a global or another address that
does not move after `install`:

```zig
const std = @import("std");
const kron = @import("kron");

var failure: kron.FailureHandler = undefined;

pub fn main(init: std.process.Init) !void {
    failure = try kron.FailureHandler.init(init.io, .{
        .directory = "crash",
        .program_name = "myapp",
    });
    try failure.install();
    defer failure.uninstall();

    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{.{ .target = .{ .file = .{ .path = "app.log" } } }},
        // Optional: make `.fatal` a terminating event. Off by default.
        .failure_handler = &failure,
    });
    defer logging.destroy();

    logging.scoped("app").info("started", .{});
    try logging.shutdown();
}
```

`init` creates `directory` when missing and copies the program, host, and user
components. `program_name` defaults to the basename of `/proc/self/cmdline[0]`
on Linux and `"kron"` elsewhere. `host_name`/`user_name` default to the system
hostname and `USER` (with libc); unavailable values become `unknown`.

Only one handler can be installed process-wide. `install` returns
`error.AlreadyInstalled` for a second handler. Install before starting worker
threads and uninstall after they stop; uninstall restores the previous signal
actions.

## Crash file naming and content

Reports use the glog-style name:

```text
<directory>/<program>.<host>.<user>.log.FATAL.<YYYYMMDD-HHMMSS>.<pid>
```

The timestamp is UTC. A collision adds `-<attempt>` before the end of the name.
`<directory>/<program>.FATAL` is replaced with a relative symlink to the newest
report when `create_latest_symlink` is enabled.

Each report contains:

- capture time in UTC and Unix seconds;
- signal name/number, signal code, and fault address for signal reports;
- PID/TID, program, host, and user;
- reason and optional message;
- raw return addresses (`#0 0x...`) for every captured frame;
- an optional symbolized trace.

`record(reason, message)` writes one report and returns without terminating.
It is useful for non-fatal diagnostics and is the only mode that returns a
file-write error (`error.CrashFileUnavailable`) while still attempting the
stderr mirror. `fatal(message)` writes one report and aborts with `SIGABRT`.

## Signals and fatal events

The default signal set is `SIGSEGV`, `SIGILL`, `SIGFPE`, `SIGABRT`, `SIGBUS`,
and `SIGTERM`, matching glog's POSIX set. `Options.signals` can select a subset.
After writing, the handler restores the default action and re-raises the
signal, so the process still terminates by the original signal.

When `Logging` is created with `.failure_handler = &handler` and the handler was
initialized with `.abort_on_fatal = true`, a delivered `.fatal` event calls
`fatal(event.message)` after dispatch. `abort_on_fatal` is off by default
because kron's `.fatal` severity is otherwise a non-terminating level. The
crash file is the authoritative record for that fatal call; a queued
asynchronous copy of the same event is not flushed before the abort. Events
rejected by filtering or sampling never reach dispatch and therefore do not
trigger the fatal hook.

Direct `Runtime` users can call `record`/`fatal` explicitly; the `Logging` hook
is only a convenience for the application entry point. The composite
`Logging.scoped` logger uses the hook; `Logging.scopedOutput` and direct
`Runtime` loggers bypass it, so call `fatal` explicitly when those paths are
used.

## Safety boundaries

The signal path uses fixed storage and `openat`/`write`/`symlink`/`raise`
operations. It does not allocate, take logging locks, or drain the runtime.
The following boundaries are deliberate:

- **Symbolization is best-effort.** Zig's debug-info reader may allocate and
  take internal locks. Raw return addresses are always written; set
  `capture_stack_trace = false` and `symbolize_stack_trace = false` for a
  strictly fixed-allocation signal path.
- **Alternate signal stacks are per-thread.** `install` installs one for the
  calling thread. Call `installThreadSignalStack()` from every thread that
  should survive stack-overflow capture.
- **The crash file is not durable evidence.** It is written with ordinary
  writes and a best-effort `fsync`; it does not replace journal recovery or
  power-loss qualification.
- **Relative directories resolve at crash time.** Use an absolute directory
  when the process may change its working directory.
- **POSIX signal handlers are unavailable on Windows.** `init` and `record`
  still compile, but installing signal handlers returns
  `error.SignalHandlersUnsupported` and file-backed reports are unavailable.
- **One process-wide handler.** A second `install` is rejected instead of
  silently replacing the first.

## Verification

`zig build test-failure-handler -Doptimize=ReleaseSafe -j1` builds a real child
workload and verifies:

- `record` produces one report, exits 0, and updates the symlink;
- `fatal` and a `.fatal` `Logging` event terminate with `SIGABRT` and produce
  exactly one report with the expected message;
- real `SIGSEGV`, `SIGABRT`, and `SIGTERM` terminate with the original signal;
- reports contain the signal, code, fault address, PID/TID, program/host/user,
  and at least one raw stack address;
- stderr mirrors the report header and signal name.

The step is part of `zig build test`. It does not qualify symbolization on
stripped binaries, alternate-stack coverage for threads that never installed a
stack, or crash-file persistence across system power loss.
