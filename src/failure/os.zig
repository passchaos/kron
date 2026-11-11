//! Minimal OS layer for the crash path.
//!
//! The report writer must remain callable from a signal handler, so this file
//! deliberately uses `openat`/`write`/`symlinkat`/`unlinkat` wrappers instead
//! of buffered or allocating I/O. Unsupported targets keep compiling: install
//! reports `error.SignalHandlersUnsupported` and record/fatal fall back to
//! stderr only.
const std = @import("std");
const builtin = @import("builtin");
const signal = @import("signal.zig");

pub const posix = switch (builtin.os.tag) {
    .windows, .wasi, .freestanding, .emscripten => false,
    else => true,
};

pub const signals_supported = posix and switch (builtin.os.tag) {
    .linux,
    .macos,
    .ios,
    .tvos,
    .watchos,
    .visionos,
    .maccatalyst,
    .driverkit,
    .freebsd,
    .netbsd,
    .openbsd,
    .dragonfly,
    .illumos,
    => true,
    else => false,
};

pub const fd_t = if (posix) std.posix.fd_t else i32;
pub const DirHandle = std.Io.Dir.Handle;
pub const at_fdcwd: DirHandle = if (posix) std.posix.AT.FDCWD else @ptrFromInt(1);
pub const PosixSignal = if (signals_supported) std.posix.SIG else void;
pub const StoredAction = if (signals_supported) std.posix.Sigaction else void;

pub const OpenError = error{ PathAlreadyExists, OpenFailed };

/// Writes every byte or reports failure. Partial writes and `EINTR` are
/// retried; no allocation, locks, or buffering are involved.
pub fn writeAll(fd: fd_t, bytes: []const u8) bool {
    if (comptime !posix) {
        return false;
    } else {
        var written: usize = 0;
        while (written < bytes.len) {
            const result = std.posix.system.write(fd, bytes.ptr + written, bytes.len - written);
            switch (std.posix.errno(result)) {
                .SUCCESS => {
                    const count: usize = @intCast(result);
                    if (count == 0) return false;
                    written += count;
                },
                .INTR => continue,
                else => return false,
            }
        }
        return true;
    }
}

pub fn writeStderr(bytes: []const u8) bool {
    if (comptime !posix) {
        return false;
    } else {
        return writeAll(std.posix.STDERR_FILENO, bytes);
    }
}

/// Opens a new crash file with mode 0600 relative to `dir_fd`. The caller
/// retries with a different name on `PathAlreadyExists`.
pub fn openExclusiveAt(dir_fd: DirHandle, path: [:0]const u8) OpenError!fd_t {
    if (comptime !posix) {
        return error.OpenFailed;
    } else {
        return std.posix.openat(dir_fd, path, .{
            .ACCMODE = .WRONLY,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
        }, 0o600) catch |err| switch (err) {
            error.PathAlreadyExists => error.PathAlreadyExists,
            else => error.OpenFailed,
        };
    }
}

pub fn close(fd: fd_t) void {
    if (comptime posix) _ = std.posix.system.close(fd);
}

/// Best-effort data synchronization. Crash files are diagnostic, not a
/// durability protocol, so this is opt-in and failure is ignored.
pub fn sync(fd: fd_t) void {
    if (comptime posix) _ = std.posix.system.fsync(fd);
}

/// Replaces the stable `<program>.FATAL` link relative to `dir_fd`. Unlink and
/// symlink are both async-signal-safe; failure leaves the previous link intact.
pub fn replaceSymlinkAt(dir_fd: DirHandle, link_path: [:0]const u8, target: [:0]const u8) void {
    if (comptime !posix) {
        return;
    } else {
        _ = std.posix.system.unlinkat(dir_fd, link_path, 0);
        _ = std.posix.system.symlinkat(target, dir_fd, link_path);
    }
}

/// Removes `sig` from the calling thread's signal mask. Used after re-raising
/// a fatal signal so a previously blocked signal cannot leave the process
/// alive in the handler return path.
pub fn unblockSignal(sig: PosixSignal) void {
    if (comptime !signals_supported) {
        return;
    } else {
        var set = std.posix.sigemptyset();
        std.posix.sigaddset(&set, sig);
        std.posix.sigprocmask(std.posix.SIG.UNBLOCK, &set, null);
    }
}

/// Last-resort termination with the shell convention `128 + signal`.
pub fn exitSignal(sig: PosixSignal) noreturn {
    if (comptime !signals_supported) {
        std.process.abort();
    } else {
        const number: u8 = @intCast(@intFromEnum(sig));
        if (comptime builtin.link_libc) {
            std.c._exit(128 + number);
        } else if (comptime builtin.os.tag == .linux) {
            std.os.linux.exit_group(128 + number);
        } else {
            std.process.abort();
        }
    }
}

pub fn getpid() i32 {
    if (comptime builtin.os.tag == .windows) {
        return @intCast(std.os.windows.GetCurrentProcessId());
    } else if (comptime builtin.link_libc) {
        return @intCast(std.c.getpid());
    } else if (comptime builtin.os.tag == .linux) {
        return @intCast(std.os.linux.getpid());
    } else {
        return 0;
    }
}

pub fn gettid() i32 {
    if (comptime builtin.os.tag == .linux) {
        return @intCast(std.os.linux.gettid());
    } else {
        return getpid();
    }
}

pub fn timestampSeconds() i64 {
    if (comptime !posix) {
        return 0;
    } else {
        var timestamp: std.posix.timespec = undefined;
        if (comptime builtin.link_libc) {
            if (std.c.clock_gettime(std.posix.CLOCK.REALTIME, &timestamp) != 0) return 0;
        } else if (comptime builtin.os.tag == .linux) {
            if (std.os.linux.errno(std.os.linux.clock_gettime(.REALTIME, &timestamp)) != .SUCCESS) return 0;
        } else {
            return 0;
        }
        return @intCast(timestamp.sec);
    }
}

pub fn toPosixSignal(value: signal.Signal) PosixSignal {
    if (comptime !signals_supported) {
        return {};
    } else {
        return switch (value) {
            .segv => .SEGV,
            .ill => .ILL,
            .fpe => .FPE,
            .abrt => .ABRT,
            .bus => .BUS,
            .term => .TERM,
        };
    }
}

pub fn defaultAction() StoredAction {
    if (comptime !signals_supported) {
        return {};
    } else {
        return .{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
    }
}

/// Installs a caller-owned alternate signal stack for stack-overflow capture.
pub fn installSignalStack(stack: []align(16) u8) void {
    if (comptime !signals_supported) {
        return;
    } else {
        std.posix.sigaltstack(&.{
            .sp = @ptrCast(stack.ptr),
            .size = @intCast(stack.len),
            .flags = 0,
        }, null) catch {};
    }
}
