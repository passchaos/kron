# Platform support and capability boundaries

Target platforms are **Windows, Linux, macOS, Android, and iOS**. File, journal,
clock, and thread interfaces use a common public API; OS-specific mapping,
preallocation, and synchronization implementations live in
`src/platform/mapping/{linux,windows,darwin}.zig`. Shared journals currently
require a 64-bit little-endian target; 32-bit journals are not qualified.

| Platform | File and shared journal implementation | File backend/clock | Current verification |
| --- | --- | --- | --- |
| Linux x86_64/aarch64 | fallocate, MAP_SHARED, msync, file/dir fsync | portable, optional io_uring; NativeClock; optional x86_64 TSC | x86_64 real-machine execution/crash gates; ReleaseSafe object compilation of public call paths on both architectures |
| Windows x86_64 | FileAllocationInformation, CreateFileMappingW/MapViewOfFile, FlushViewOfFile, file flush | portable; standard-library native system-clock fallback | Complete public call-path object compilation; Windows backend PE linking and KERNEL32/ntdll import checks; independent Zig package consumer PE linking; no real-device execution yet |
| macOS arm64/x86_64 | F_PREALLOCATE, MAP_SHARED, msync, fsync; strict durable adds F_FULLFSYNC | portable; standard-library native system-clock fallback | Mach-O object compilation of real public paths on both architectures; no real-device execution yet |
| Android arm64/x86_64 | Linux mapping implementation; app-writable filesystem paths | portable; optional io_uring where allowed; NativeClock | Android ABI public call-path object compilation; no device execution yet |
| iOS arm64/device and arm64/simulator | Darwin mapping implementation; app sandbox writable paths | portable; standard-library native system-clock fallback | Mach-O object compilation of real public paths for device/simulator; no device execution yet |

`zig build check-platforms -j1` forces actual object generation for nine
targets. The `src/platform_check.zig` entry exercises synchronous file writes,
static clocks, filter reload, flush/deadline/shutdown, SPSC attach/emit/detach,
schema-capable journals, and recovery Reader. This covers more real paths than a
declaration-only check, but **cross-compilation does not prove successful
execution, syscall availability, or device durability**. Apple app linking needs
a normal Xcode SDK/libSystem; Android app linking needs a normal NDK/bionic. The
host object check does not install or substitute for those SDKs.

The optional [failure handler](failure-handler.md) installs POSIX signal
handlers and writes crash files on Linux, macOS, Android, and iOS targets.
Windows keeps the API compiling and can emit stderr diagnostics, but signal
installation returns `error.SignalHandlersUnsupported`. Cross-compilation of the
failure module is part of `check-platforms`; it is not target-device execution.

`kron.platform` provides compile-time `target`, `synchronous`, `shared_journal`,
`asynchronous`, `spsc`, `directory_durable_protocol`, `io_uring`, and `tsc`.
Capability values mean the implementation exists; runtime disk, permissions,
kernel, app sandbox, or filesystem can still return explicit errors. The
automatic backend selects portable when io_uring is unavailable.

System local time is an explicit optional capability:
`.timestamp = .{ .zone = .local }`. Linux enables it through the dependency's
`system-local-time=true` or by linking libc in the application; the default
fixed-offset path adds no libc dependency. Apple/Android use system libc localtime
conversion, and Windows uses the native dynamic timezone API. The asynchronous
consumer caches per event Unix second, while the producer keeps raw timestamp
capture. See [time documentation](time.md#system-local-time) for timezone-source
identity, keeping the timezone environment stable at runtime, and historical
non-minute-offset errors. Linux local-time measurements and other-target object
compilation are recorded separately and do not replace non-Linux device
qualification.

## Synchronization and durability

Explicit durable protocols differ between page synchronization and file
synchronization on each platform. Mmap journal initialization and schema-ready
complete through the file publication protocol; on Linux/Android, whole-file
fsync already covers shared-mapping dirty pages, so cold publication omits the
preceding duplicate msync, while other platforms keep mapping flush. See
[Mmap publication](mmap-publication.md). Accepted means the event was completely
committed to the shared file mapping; Memory asynchronous acceptance only enters
an in-process queue. Neither replaces device power-loss durable confirmation; see
[asynchronous storage](async-storage.md).

Linux/Android strict durable performs msync, file sync, and parent-directory
sync. Darwin strict durable additionally performs F_FULLFSYNC and returns
`UnsupportedDurability` if the file/directory does not support this protocol
rather than downgrading to an ordinary successful flush. Darwin preallocation
checks allocated blocks and requests only the difference; failure falls back to
rechecking so reopening a journal does not repeatedly grow actual disk
reservation.

Windows can flush pages and files, but this implementation has no equivalent
protocol that confirms durability of a newly created directory entry, so
`directory_durable_protocol=false`, and file sink/journal strict durable returns
`UnsupportedDurability`. Synchronous written and ordinary mmap async/process-crash
recovery remain available. FlushViewOfFile is not treated as a complete device
durability guarantee.

Mobile applications must pass sandbox paths from the host; the logging library
does not request extra permissions or guarantee execution while the system is
suspended. Applications must explicitly flush/shutdown in platform lifecycle
callbacks and handle the results. iOS protected files may be inaccessible while
locked or suspended; Android kernel policy may reject io_uring. Both are handled
through actual I/O results.

## Execution verification

```sh
zig build verify-local -Doptimize=ReleaseFast -j1
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build test-package test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-platform-host -Doptimize=ReleaseSafe -j1
```

The independent Zig package consumer actually ran five modes on Linux and linked
a Windows PE; that evidence is no longer tracked. The test driver selects the
Windows `.exe` suffix per host; reports include the actual host, toolchain, and
thread count. Only the Linux single-threaded run uses `/proc/self/task` to confirm
the OS thread count; other platforms do not record a missing check as a pass. See
[Zig package integration](package.md) for source-archive consumption.

Single-threaded builds support only the synchronous runtime; ordinary file flush,
durable capabilities, and shutdown are available, timed control returns
`TimedControlUnavailable`, and async/SPSC initialization returns
`ThreadsUnavailable`. The current Linux executable confirms a single process
thread and no new runtime allocation for submit/flush after initialization.

Linux SIGKILL and child-QEMU shutdown evidence remains valid for the tested Linux
configuration; it cannot be used as Windows/Apple/Android device power-loss
qualification. Each platform must supplement execution evidence with device
runs, crash recovery, filesystem, and lifecycle tests.

## Zig self-check runnable on target devices

The independent consumer's `qualify DIRECTORY` entry uses native Zig to verify
five submission modes, Unicode file names, filter reload, zero Runtime allocation
after initialization, deep copy/redaction, ordinary and schema journal
close-reopen, read-only inspection, exclusive locking, rotation retention, and
actual durable capabilities. Results are returned as JSON; a mobile Zig host can
call `run(allocator, io, sandbox_directory)` in the same `platform.zig` without
Python or a subprocess. See [package.md](package.md) for integration.

Linux ReleaseSafe normal and single-threaded builds, a normal ReleaseFast build,
and a locally fetched source package all passed actual execution; the
single-threaded report contains only sync mode. Reusing an existing test directory
must fail and preserve existing output, and the independent package test passed.
A Windows independent application including the self-check entry linked as a PE.
Device acceptance requires running this entry on the device and saving the
report; Linux self-checks or Windows linking are not substitutes. This host has
no Wine/Android device or emulator/Apple SDK or device, so no execution reports
exist for the other four platforms.
