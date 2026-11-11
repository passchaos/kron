//! glog-style process failure capture.
//!
//! One handler can be installed per process. It optionally installs handlers
//! for fatal signals, writes a crash report with raw stack return addresses,
//! mirrors the report to stderr, and updates a stable `<program>.FATAL` link.
//! `record` writes a report without terminating; `fatal` writes a report and
//! aborts. `Logging` can bind a handler so `.fatal` events invoke `fatal`
//! after delivery when `abort_on_fatal` is enabled.
//!
//! The signal path uses fixed storage and async-signal-safe file operations.
//! Symbolization is best-effort: Zig's debug-info reader may allocate or take
//! internal locks, so raw addresses are always written and symbolization can
//! be disabled. Set `capture_stack_trace = false` as well for a strictly
//! fixed-allocation path. `sigaltstack` is per-thread; call
//! `installThreadSignalStack` from every thread that should survive
//! stack-overflow capture.
const std = @import("std");
const builtin = @import("builtin");
const os = @import("os.zig");
const report = @import("report.zig");
const trace = @import("trace.zig");
const signal_mod = @import("signal.zig");

const max_signals = signal_mod.default_signals.len;
const SignalInfo = if (os.signals_supported) std.posix.siginfo_t else void;

var active: std.atomic.Value(?*FailureHandler) = .init(null);

/// Per-thread alternate signal stack. `sigaltstack` is thread-local, so each
/// thread that calls `installThreadSignalStack` owns one of these. The storage
/// is omitted entirely on targets without signal support.
const SignalStack = if (os.signals_supported) struct {
    threadlocal var bytes: [64 * 1024]u8 align(16) = undefined;
} else struct {};

pub const FailureHandler = struct {
    pub const Signal = signal_mod.Signal;
    pub const default_signals = signal_mod.default_signals;

    pub const Options = struct {
        /// Directory for crash files. Created by `init` when missing.
        directory: []const u8,
        /// Defaults to the basename of `/proc/self/cmdline[0]` on Linux and
        /// `"kron"` elsewhere.
        program_name: ?[]const u8 = null,
        host_name: ?[]const u8 = null,
        user_name: ?[]const u8 = null,
        /// Install process-wide signal handlers. Unsupported targets return
        /// `error.SignalHandlersUnsupported`; `record`/`fatal` still work as
        /// stderr-only diagnostics.
        install_signal_handlers: bool = true,
        /// Fatal signals to capture. The default is glog's POSIX set.
        signals: []const Signal = &signal_mod.default_signals,
        /// Mirror every report to standard error.
        write_stderr: bool = true,
        /// Maintain `<program>.FATAL` as a link to the newest report.
        create_latest_symlink: bool = true,
        /// Attempt to resolve raw addresses through Zig debug info. The raw
        /// address list is emitted regardless.
        symbolize_stack_trace: bool = true,
        /// Maximum captured frames, up to `trace.max_frames`.
        max_stack_frames: usize = 64,
        /// Invoke `fatal` when a `.fatal` event is submitted through a
        /// `Logging` owner bound to this handler. Disabled by default because
        /// kron's `.fatal` severity is otherwise non-terminating.
        abort_on_fatal: bool = false,
    };

    directory: [report.max_path]u8 = undefined,
    directory_len: usize = 0,
    program: [report.max_component]u8 = undefined,
    program_len: usize = 0,
    host: [report.max_component]u8 = undefined,
    host_len: usize = 0,
    user: [report.max_component]u8 = undefined,
    user_len: usize = 0,
    install_signal_handlers: bool = false,
    write_stderr: bool = true,
    create_latest_symlink: bool = true,
    symbolize_stack_trace: bool = true,
    max_stack_frames: usize = 64,
    abort_on_fatal: bool = false,
    signals: [max_signals]Signal = undefined,
    signal_count: usize = 0,
    previous: [max_signals]os.StoredAction = undefined,
    installed: bool = false,
    handling: std.atomic.Value(bool) = .init(false),
    sequence: std.atomic.Value(u32) = .init(0),

    pub fn init(io: std.Io, options: Options) !FailureHandler {
        if (options.directory.len == 0 or options.directory.len >= report.max_path) return error.InvalidDirectory;
        if (options.signals.len == 0 or options.signals.len > max_signals) return error.InvalidSignals;
        if (options.max_stack_frames == 0 or options.max_stack_frames > trace.max_frames) return error.InvalidStackFrames;
        for (options.signals, 0..) |value, index| {
            for (options.signals[0..index]) |previous| {
                if (previous == value) return error.DuplicateSignal;
            }
        }
        try std.Io.Dir.cwd().createDirPath(io, options.directory);

        var self: FailureHandler = .{};
        @memcpy(self.directory[0..options.directory.len], options.directory);
        self.directory_len = options.directory.len;
        self.program_len = resolveProgram(&self.program, options.program_name);
        self.host_len = resolveHost(&self.host, options.host_name);
        self.user_len = resolveUser(&self.user, options.user_name);
        self.install_signal_handlers = options.install_signal_handlers;
        self.write_stderr = options.write_stderr;
        self.create_latest_symlink = options.create_latest_symlink;
        self.symbolize_stack_trace = options.symbolize_stack_trace;
        self.max_stack_frames = options.max_stack_frames;
        self.abort_on_fatal = options.abort_on_fatal;
        @memcpy(self.signals[0..options.signals.len], options.signals);
        self.signal_count = options.signals.len;
        return self;
    }

    /// Installs process-wide signal handlers. The handler must stay at a
    /// stable address until `uninstall`; do not move the value after install.
    pub fn install(self: *FailureHandler) !void {
        if (self.installed) return error.AlreadyInstalled;
        if (active.cmpxchgStrong(null, self, .acq_rel, .acquire) != null) return error.AlreadyInstalled;
        errdefer _ = active.cmpxchgStrong(self, null, .acq_rel, .acquire);
        if (self.install_signal_handlers) {
            if (comptime !os.signals_supported) return error.SignalHandlersUnsupported;
            self.installSignals();
        }
        self.installed = true;
    }

    pub fn uninstall(self: *FailureHandler) void {
        if (!self.installed) return;
        if (self.install_signal_handlers) {
            if (comptime os.signals_supported) {
                for (self.signals[0..self.signal_count], 0..) |value, index| {
                    std.posix.sigaction(os.toPosixSignal(value), &self.previous[index], null);
                }
            }
        }
        self.installed = false;
        _ = active.cmpxchgStrong(self, null, .acq_rel, .acquire);
    }

    pub fn abortOnFatal(self: *const FailureHandler) bool {
        return self.abort_on_fatal;
    }

    /// Writes one crash report without terminating. Returns
    /// `error.CrashFileUnavailable` when no file could be created; the stderr
    /// mirror is still attempted.
    pub fn record(self: *FailureHandler, reason: []const u8, message: []const u8) !void {
        var frames: [trace.max_frames]usize = undefined;
        const captured = trace.capture(frames[0..self.max_stack_frames], .{ .first_address = @returnAddress() });
        return self.writeReport("report", reason, message, null, 0, null, captured);
    }

    /// Writes a fatal report and aborts. The SIGABRT handler is suppressed for
    /// this process-wide handler so one fatal call produces one report.
    pub fn fatal(self: *FailureHandler, message: []const u8) noreturn {
        if (self.handling.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) {
            var frames: [trace.max_frames]usize = undefined;
            const captured = trace.capture(frames[0..self.max_stack_frames], .{ .first_address = @returnAddress() });
            self.writeReport("fatal", "fatal", message, null, 0, null, captured) catch {};
        }
        std.process.abort();
    }

    /// Installs a per-thread alternate signal stack for stack-overflow capture.
    /// `sigaltstack` is per-thread, so callers must invoke this on every thread
    /// that should be covered. Repeated calls replace the previous stack.
    pub fn installThreadSignalStack() void {
        if (comptime !os.signals_supported) {
            return;
        } else {
            os.installSignalStack(&SignalStack.bytes);
        }
    }

    fn installSignals(self: *FailureHandler) void {
        if (comptime !os.signals_supported) return;
        installThreadSignalStack();
        const flags = std.posix.SA.SIGINFO | std.posix.SA.RESETHAND |
            (if (@hasDecl(std.posix.SA, "ONSTACK")) std.posix.SA.ONSTACK else 0);
        var action: os.StoredAction = .{
            .handler = .{ .sigaction = handleSignal },
            .mask = std.posix.sigemptyset(),
            .flags = flags,
        };
        for (self.signals[0..self.signal_count], 0..) |value, index| {
            std.posix.sigaction(os.toPosixSignal(value), &action, &self.previous[index]);
        }
    }

    fn writeReport(
        self: *FailureHandler,
        kind: []const u8,
        reason: []const u8,
        message: []const u8,
        signal_value: ?Signal,
        signal_code: i32,
        fault_address: ?usize,
        captured: std.debug.StackTrace,
    ) !void {
        var path_buffer: [report.max_path]u8 = undefined;
        var zero_buffer: [report.max_path + 1]u8 = undefined;
        var opened: ?os.fd_t = null;
        var final_path: ?[:0]const u8 = null;
        var attempt: u32 = 0;
        const unix = os.timestampSeconds();
        while (attempt < 8) : (attempt += 1) {
            const name = report.fileName(
                &path_buffer,
                self.directorySlice(),
                self.programSlice(),
                self.hostSlice(),
                self.userSlice(),
                unix,
                os.getpid(),
                attempt,
            ) catch break;
            const zero = std.fmt.bufPrintZ(&zero_buffer, "{s}", .{name}) catch break;
            opened = os.openExclusive(zero) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => break,
            };
            final_path = zero;
            break;
        }
        const file = opened;
        self.emitReport(file, unix, kind, reason, message, signal_value, signal_code, fault_address, captured);
        if (file) |handle| {
            os.sync(handle);
            os.close(handle);
        }
        if (final_path) |path| {
            if (self.create_latest_symlink) self.updateLatestLink(path);
        }
        if (file == null) return error.CrashFileUnavailable;
    }

    fn updateLatestLink(self: *FailureHandler, path: [:0]const u8) void {
        var link_buffer: [report.max_path]u8 = undefined;
        var zero_link: [report.max_path + 1]u8 = undefined;
        var zero_target: [report.max_path + 1]u8 = undefined;
        const link = report.latestLink(&link_buffer, self.directorySlice(), self.programSlice()) catch return;
        const target = std.fs.path.basename(path);
        const zero_link_value = std.fmt.bufPrintZ(&zero_link, "{s}", .{link}) catch return;
        const zero_target_value = std.fmt.bufPrintZ(&zero_target, "{s}", .{target}) catch return;
        os.replaceSymlink(zero_link_value, zero_target_value);
    }

    fn writeSignalReport(self: *FailureHandler, sig: os.PosixSignal, info: *const SignalInfo, context: ?*anyopaque) void {
        if (comptime !os.signals_supported) {
            return;
        } else {
            var frames: [trace.max_frames]usize = undefined;
            const captured = trace.captureFromSignal(context, frames[0..self.max_stack_frames]);
            self.writeReport(
                "signal",
                "fatal signal",
                "",
                fromPosixSignal(sig),
                info.code,
                faultAddress(info),
                captured,
            ) catch {};
        }
    }

    fn emitReport(
        self: *FailureHandler,
        fd: ?os.fd_t,
        unix: i64,
        kind: []const u8,
        reason: []const u8,
        message: []const u8,
        signal_value: ?Signal,
        signal_code: i32,
        fault_address: ?usize,
        captured: std.debug.StackTrace,
    ) void {
        var timestamp_buffer: [32]u8 = undefined;
        const timestamp = report.formatIsoTimestamp(&timestamp_buffer, unix) catch "unknown";
        const title = if (std.mem.eql(u8, kind, "signal") or std.mem.eql(u8, kind, "fatal"))
            "*** kron failure handler ***\n"
        else
            "*** kron failure report ***\n";
        self.emit(fd, "{s}", .{title});
        self.emit(fd, "Captured at {s} (unix={d})\n", .{ timestamp, unix });
        if (signal_value) |value| {
            if (comptime os.signals_supported) {
                self.emit(fd, "Signal: {s} ({d})\n", .{ report.signalLabel(value), @intFromEnum(os.toPosixSignal(value)) });
            } else {
                self.emit(fd, "Signal: {s}\n", .{report.signalLabel(value)});
            }
            self.emit(fd, "Signal code: {d}\n", .{signal_code});
            if (fault_address) |address| {
                self.emit(fd, "Fault address: 0x{x}\n", .{address});
            } else {
                self.emit(fd, "Fault address: unavailable\n", .{});
            }
        }
        self.emit(fd, "PID: {d} TID: {d}\n", .{ os.getpid(), os.gettid() });
        self.emit(fd, "Program: {s}\nHost: {s}\nUser: {s}\n", .{
            self.programSlice(),
            self.hostSlice(),
            self.userSlice(),
        });
        self.emit(fd, "Reason: {s}\n", .{reason});
        if (message.len != 0) self.emit(fd, "Message: {s}\n", .{message});
        self.emit(fd, "\nStack trace:\n", .{});
        if (captured.return_addresses.len == 0) {
            self.emit(fd, "  (no stack frames captured)\n", .{});
        } else {
            for (captured.return_addresses, 0..) |address, index| {
                self.emit(fd, "  #{d} 0x{x}\n", .{ index, address });
            }
        }
        if (self.symbolize_stack_trace) {
            var symbol_buffer: [16 * 1024]u8 = undefined;
            const symbols = trace.symbolize(&symbol_buffer, &captured);
            if (symbols.len != 0) {
                self.emit(fd, "\nSymbolized stack trace:\n", .{});
                self.emitBytes(fd, symbols);
            }
        }
    }

    fn emit(self: *FailureHandler, fd: ?os.fd_t, comptime fmt: []const u8, args: anytype) void {
        var buffer: [512]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, fmt, args) catch return;
        self.emitBytes(fd, text);
    }

    fn emitBytes(self: *FailureHandler, fd: ?os.fd_t, bytes: []const u8) void {
        if (fd) |handle| _ = os.writeAll(handle, bytes);
        if (self.write_stderr) {
            if (!os.writeStderr(bytes)) {
                if (comptime !os.posix) std.debug.print("{s}", .{bytes});
            }
        }
    }

    fn directorySlice(self: *const FailureHandler) []const u8 {
        return self.directory[0..self.directory_len];
    }

    fn programSlice(self: *const FailureHandler) []const u8 {
        return self.program[0..self.program_len];
    }

    fn hostSlice(self: *const FailureHandler) []const u8 {
        return self.host[0..self.host_len];
    }

    fn userSlice(self: *const FailureHandler) []const u8 {
        return self.user[0..self.user_len];
    }
};

fn emptyTrace() std.debug.StackTrace {
    return .{ .return_addresses = &.{}, .skipped = .none };
}

fn handleSignal(sig: os.PosixSignal, info: *const SignalInfo, context: ?*anyopaque) callconv(.c) void {
    if (comptime !os.signals_supported) {
        return;
    } else {
        const handler = active.load(.acquire) orelse return reraise(sig);
        if (handler.handling.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return reraise(sig);
        handler.writeSignalReport(sig, info, context);
        reraise(sig);
    }
}

fn reraise(sig: os.PosixSignal) void {
    if (comptime os.signals_supported) {
        var action = os.defaultAction();
        std.posix.sigaction(sig, &action, null);
        // The signal is blocked while the handler runs. Returning from the
        // handler delivers the pending default action.
        std.posix.raise(sig) catch std.process.abort();
    } else {
        std.process.abort();
    }
}

fn fromPosixSignal(value: os.PosixSignal) ?signal_mod.Signal {
    if (comptime !os.signals_supported) {
        return null;
    } else {
        return switch (value) {
            .SEGV => .segv,
            .ILL => .ill,
            .FPE => .fpe,
            .ABRT => .abrt,
            .BUS => .bus,
            .TERM => .term,
            else => null,
        };
    }
}

fn faultAddress(info: *const SignalInfo) ?usize {
    if (comptime !os.signals_supported) {
        return null;
    } else if (comptime builtin.os.tag == .linux) {
        if (info.code <= 0) return null;
        return @intFromPtr(info.fields.sigfault.addr);
    } else if (comptime builtin.os.tag == .macos or builtin.os.tag == .ios or
        builtin.os.tag == .tvos or builtin.os.tag == .watchos or
        builtin.os.tag == .visionos or builtin.os.tag == .maccatalyst or builtin.os.tag == .driverkit)
    {
        if (info.code <= 0) return null;
        return @intFromPtr(info.addr);
    } else {
        return null;
    }
}

fn resolveProgram(destination: []u8, override: ?[]const u8) usize {
    if (override) |value| return report.sanitize(destination, value).len;
    if (comptime builtin.os.tag == .linux) {
        var command_buffer: [report.max_component * 4]u8 = undefined;
        if (readSelfCommand(&command_buffer)) |command| {
            return report.sanitize(destination, std.fs.path.basename(command)).len;
        }
    }
    return report.sanitize(destination, "kron").len;
}

fn readSelfCommand(buffer: []u8) ?[]const u8 {
    if (comptime builtin.os.tag != .linux) {
        return null;
    } else {
        const fd = std.posix.openat(std.posix.AT.FDCWD, "/proc/self/cmdline", .{
            .ACCMODE = .RDONLY,
            .CLOEXEC = true,
        }, 0) catch return null;
        defer _ = std.posix.system.close(fd);
        const count = std.posix.read(fd, buffer) catch return null;
        if (count == 0) return null;
        const end = std.mem.indexOfScalar(u8, buffer[0..count], 0) orelse count;
        if (end == 0) return null;
        return buffer[0..end];
    }
}

fn resolveHost(destination: []u8, override: ?[]const u8) usize {
    if (override) |value| return report.sanitize(destination, value).len;
    if (comptime os.posix) {
        var host_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
        if (std.posix.gethostname(&host_buffer)) |value| {
            return report.sanitize(destination, value).len;
        } else |_| {}
    } else {
        return report.sanitize(destination, "unknown").len;
    }
    return report.sanitize(destination, "unknown").len;
}

fn resolveUser(destination: []u8, override: ?[]const u8) usize {
    if (override) |value| return report.sanitize(destination, value).len;
    if (comptime os.posix and builtin.link_libc) {
        if (std.c.getenv("USER")) |value| {
            return report.sanitize(destination, std.mem.span(value)).len;
        }
    }
    return report.sanitize(destination, "unknown").len;
}

test "init rejects invalid options" {
    var handler = FailureHandler.init(std.testing.io, .{ .directory = "" });
    try std.testing.expectError(error.InvalidDirectory, handler);
    handler = FailureHandler.init(std.testing.io, .{ .directory = ".zig-cache/failure-invalid", .signals = &.{} });
    try std.testing.expectError(error.InvalidSignals, handler);
    handler = FailureHandler.init(std.testing.io, .{ .directory = ".zig-cache/failure-invalid", .max_stack_frames = 0 });
    try std.testing.expectError(error.InvalidStackFrames, handler);
    handler = FailureHandler.init(std.testing.io, .{ .directory = ".zig-cache/failure-invalid", .signals = &.{ .segv, .segv } });
    try std.testing.expectError(error.DuplicateSignal, handler);
}

test "record writes a report and updates the latest link" {
    if (comptime !os.posix) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var path_buffer: [report.max_path]u8 = undefined;
    const directory = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var handler = try FailureHandler.init(std.testing.io, .{
        .directory = directory,
        .program_name = "unit-failure",
        .host_name = "unit-host",
        .user_name = "unit-user",
        .install_signal_handlers = false,
        .write_stderr = false,
        .symbolize_stack_trace = false,
    });
    try handler.record("unit reason", "unit message");

    var found_name: ?[128]u8 = null;
    var found_len: usize = 0;
    var iterator = tmp.dir.iterate();
    while (try iterator.next(std.testing.io)) |entry| {
        if (std.mem.indexOf(u8, entry.name, ".FATAL.") != null) {
            var name_buffer: [128]u8 = undefined;
            @memcpy(name_buffer[0..entry.name.len], entry.name);
            found_name = name_buffer;
            found_len = entry.name.len;
        }
    }
    try std.testing.expect(found_len != 0);
    const name = found_name.?[0..found_len];
    const contents = try tmp.dir.readFileAlloc(std.testing.io, name, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "*** kron failure report ***") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Reason: unit reason") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Message: unit message") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Stack trace:") != null);

    var link_buffer: [128]u8 = undefined;
    const target = try tmp.dir.readLink(std.testing.io, "unit-failure.FATAL", &link_buffer);
    try std.testing.expectEqualStrings(name, link_buffer[0..target]);
}
