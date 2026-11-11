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
//! Signal reports contain raw addresses by default; symbolization is opt-in
//! because Zig's debug-info reader may allocate or take internal locks. Set
//! `capture_stack_trace = false` as well for a strictly fixed-allocation path.
//! `sigaltstack` is per-thread; call `installThreadSignalStack` from every
//! thread that should survive stack-overflow capture.
const std = @import("std");
const builtin = @import("builtin");
const os = @import("os.zig");
const report = @import("report.zig");
const trace = @import("trace.zig");
const signal_mod = @import("signal.zig");

const max_signals = signal_mod.default_signals.len;
const SignalInfo = if (os.signals_supported) std.posix.siginfo_t else void;

const ReportKind = enum {
    signal,
    report,
    fatal,

    fn title(self: ReportKind) []const u8 {
        return switch (self) {
            .signal, .fatal => "*** kron failure handler ***\n",
            .report => "*** kron failure report ***\n",
        };
    }
};

var active: std.atomic.Value(?*FailureHandler) = .init(null);

/// Per-thread alternate signal stack. `sigaltstack` is thread-local, so each
/// thread that calls `installThreadSignalStack` owns one of these. The storage
/// is omitted entirely on targets without signal support.
const SignalStack = if (os.signals_supported) struct {
    threadlocal var bytes: [64 * 1024]u8 align(16) = undefined;
} else struct {};

/// Signal-path report storage. `handling` guarantees one signal report at a
/// time; `record`/`fatal` use caller stack storage instead.
var signal_report_buffer: [report.max_report_bytes]u8 = undefined;

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
        /// Mirror every report to standard error after the crash file write.
        write_stderr: bool = true,
        /// Maintain `<program>.FATAL` as a link to the newest report.
        create_latest_symlink: bool = true,
        /// Attempt to resolve raw addresses through Zig debug info for
        /// `record` and `fatal`. The raw address list is emitted regardless.
        symbolize_stack_trace: bool = true,
        /// Attempt to resolve raw addresses for signal reports. On by default
        /// to match glog; the raw report is written before symbolization, so a
        /// debug-info failure cannot remove the raw evidence. Disable for a
        /// strictly fixed-allocation signal path.
        symbolize_signal_stack_trace: bool = true,
        /// Capture stack return addresses. Disable together with signal
        /// symbolization for a strictly fixed-allocation signal path.
        capture_stack_trace: bool = true,
        /// Call `fsync` on the crash file before closing it. Off by default:
        /// the crash file is diagnostic, not a durability protocol.
        sync_crash_file: bool = false,
        /// Maximum captured frames, up to `trace.max_frames`.
        max_stack_frames: usize = 64,
        /// Invoke `fatal` when a `.fatal` event is submitted through a
        /// `Logging` owner bound to this handler. Disabled by default because
        /// kron's `.fatal` severity is otherwise non-terminating.
        abort_on_fatal: bool = false,
    };

    io: std.Io = undefined,
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
    symbolize_signal_stack_trace: bool = true,
    capture_stack_trace: bool = true,
    sync_crash_file: bool = false,
    max_stack_frames: usize = 64,
    abort_on_fatal: bool = false,
    signals: [max_signals]Signal = undefined,
    signal_count: usize = 0,
    previous: [max_signals]os.StoredAction = undefined,
    directory_handle: ?std.Io.Dir = null,
    installed: bool = false,
    handling: std.atomic.Value(bool) = .init(false),

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
        self.io = io;
        @memcpy(self.directory[0..options.directory.len], options.directory);
        self.directory_len = options.directory.len;
        self.program_len = resolveProgram(&self.program, options.program_name);
        self.host_len = resolveHost(&self.host, options.host_name);
        self.user_len = resolveUser(&self.user, options.user_name);
        self.install_signal_handlers = options.install_signal_handlers;
        self.write_stderr = options.write_stderr;
        self.create_latest_symlink = options.create_latest_symlink;
        self.symbolize_stack_trace = options.symbolize_stack_trace;
        self.symbolize_signal_stack_trace = options.symbolize_signal_stack_trace;
        self.capture_stack_trace = options.capture_stack_trace;
        self.sync_crash_file = options.sync_crash_file;
        self.max_stack_frames = options.max_stack_frames;
        self.abort_on_fatal = options.abort_on_fatal;
        @memcpy(self.signals[0..options.signals.len], options.signals);
        self.signal_count = options.signals.len;
        return self;
    }

    /// Installs process-wide signal handlers and opens the crash directory.
    /// The handler must stay at a stable address until `uninstall`; do not move
    /// the value after install.
    pub fn install(self: *FailureHandler) !void {
        if (self.installed) return error.AlreadyInstalled;
        if (self.install_signal_handlers and comptime !os.signals_supported) return error.SignalHandlersUnsupported;
        if (active.cmpxchgStrong(null, self, .acq_rel, .acquire) != null) return error.AlreadyInstalled;
        errdefer _ = active.cmpxchgStrong(self, null, .acq_rel, .acquire);
        if (comptime os.posix) {
            self.directory_handle = std.Io.Dir.cwd().openDir(self.io, self.directorySlice(), .{}) catch return error.CrashDirectoryUnavailable;
        }
        errdefer {
            if (self.directory_handle) |*dir| {
                dir.close(self.io);
                self.directory_handle = null;
            }
        }
        if (self.install_signal_handlers) self.installSignals();
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
        if (self.directory_handle) |*dir| {
            dir.close(self.io);
            self.directory_handle = null;
        }
        self.installed = false;
        _ = active.cmpxchgStrong(self, null, .acq_rel, .acquire);
    }

    pub fn abortOnFatal(self: *const FailureHandler) bool {
        return self.abort_on_fatal;
    }

    /// Writes one crash report without terminating. Returns
    /// `error.CrashFileUnavailable` when no file could be created or
    /// `error.CrashFileWriteFailed` when writing failed; the stderr mirror is
    /// still attempted in both cases.
    pub fn record(self: *FailureHandler, reason: []const u8, message: []const u8) !void {
        var frames: [trace.max_frames]usize = undefined;
        const captured = if (self.capture_stack_trace)
            trace.capture(frames[0..self.max_stack_frames], .{ .first_address = @returnAddress() })
        else
            emptyTrace();
        var buffer: [report.max_report_bytes]u8 = undefined;
        return self.writeReport(&buffer, .report, reason, message, null, 0, null, captured, self.symbolize_stack_trace);
    }

    /// Writes a fatal report and aborts. The SIGABRT handler is suppressed for
    /// this process-wide handler so one fatal call produces one report.
    pub fn fatal(self: *FailureHandler, message: []const u8) noreturn {
        if (self.handling.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) {
            var frames: [trace.max_frames]usize = undefined;
            const captured = if (self.capture_stack_trace)
                trace.capture(frames[0..self.max_stack_frames], .{ .first_address = @returnAddress() })
            else
                emptyTrace();
            var buffer: [report.max_report_bytes]u8 = undefined;
            self.writeReport(&buffer, .fatal, "fatal", message, null, 0, null, captured, self.symbolize_stack_trace) catch {};
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
        buffer: []u8,
        kind: ReportKind,
        reason: []const u8,
        message: []const u8,
        signal_value: ?Signal,
        signal_code: i32,
        fault_address: ?usize,
        captured: std.debug.StackTrace,
        symbolize: bool,
    ) !void {
        const unix = os.timestampSeconds();
        var writer = report.Writer.init(buffer);
        self.formatRawReport(&writer, kind, reason, message, signal_value, signal_code, fault_address, captured, unix);
        const raw_bytes = writer.finish();

        const use_dir = self.directory_handle != null;
        const pid = os.getpid();
        var name_buffer: [report.max_name + 1]u8 = undefined;
        var path_buffer: [report.max_path + 1]u8 = undefined;
        var attempt: u32 = 0;
        var opened: ?os.fd_t = null;
        var basename: []const u8 = "";
        while (attempt < 8) : (attempt += 1) {
            const zero = if (use_dir)
                report.crashNameZ(&name_buffer, self.programSlice(), self.hostSlice(), self.userSlice(), unix, pid, attempt) catch break
            else
                report.fileNameZ(&path_buffer, self.directorySlice(), self.programSlice(), self.hostSlice(), self.userSlice(), unix, pid, attempt) catch break;
            const dir_fd = if (use_dir) self.directory_handle.?.handle else os.at_fdcwd;
            opened = os.openExclusiveAt(dir_fd, zero) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => break,
            };
            basename = std.fs.path.basename(zero);
            break;
        }

        // Raw evidence reaches the file before symbolization starts. A debug
        // info failure or stall therefore cannot remove the address list.
        var file_written = false;
        if (opened) |fd| {
            file_written = os.writeAll(fd, raw_bytes);
            if (file_written and self.create_latest_symlink) self.updateLatestLink(use_dir, basename);
        }
        self.writeStderr(raw_bytes);
        if (opened != null and !file_written) {
            if (opened) |fd| os.close(fd);
            return error.CrashFileWriteFailed;
        }

        if (symbolize) {
            var symbol_writer = report.Writer.init(buffer);
            formatSymbolized(&symbol_writer, captured);
            const symbol_bytes = symbol_writer.finish();
            if (symbol_bytes.len != 0) {
                if (opened) |fd| _ = os.writeAll(fd, symbol_bytes);
                self.writeStderr(symbol_bytes);
            }
        }

        if (opened) |fd| {
            if (self.sync_crash_file) os.sync(fd);
            os.close(fd);
            return;
        }
        return error.CrashFileUnavailable;
    }

    fn updateLatestLink(self: *FailureHandler, use_dir: bool, basename: []const u8) void {
        var link_buffer: [report.max_path]u8 = undefined;
        var zero_link: [report.max_path + 1]u8 = undefined;
        var zero_target: [report.max_name + 1]u8 = undefined;
        const link = if (use_dir)
            report.latestName(&link_buffer, self.programSlice()) catch return
        else
            report.latestLink(&link_buffer, self.directorySlice(), self.programSlice()) catch return;
        const zero_link_value = std.fmt.bufPrintZ(&zero_link, "{s}", .{link}) catch return;
        const zero_target_value = std.fmt.bufPrintZ(&zero_target, "{s}", .{basename}) catch return;
        const dir_fd = if (use_dir) self.directory_handle.?.handle else os.at_fdcwd;
        os.replaceSymlinkAt(dir_fd, zero_link_value, zero_target_value);
    }

    fn writeSignalReport(self: *FailureHandler, sig: os.PosixSignal, info: *const SignalInfo, context: ?*anyopaque) void {
        if (comptime !os.signals_supported) {
            return;
        } else {
            var frames: [trace.max_frames]usize = undefined;
            const captured = if (self.capture_stack_trace)
                trace.captureFromSignal(context, frames[0..self.max_stack_frames])
            else
                emptyTrace();
            self.writeReport(
                &signal_report_buffer,
                .signal,
                "fatal signal",
                "",
                fromPosixSignal(sig),
                info.code,
                faultAddress(info),
                captured,
                self.symbolize_signal_stack_trace,
            ) catch {};
        }
    }

    fn formatRawReport(
        self: *FailureHandler,
        writer: *report.Writer,
        kind: ReportKind,
        reason: []const u8,
        message: []const u8,
        signal_value: ?Signal,
        signal_code: i32,
        fault_address: ?usize,
        captured: std.debug.StackTrace,
        unix: i64,
    ) void {
        var timestamp_buffer: [32]u8 = undefined;
        const timestamp = report.formatIsoTimestamp(&timestamp_buffer, unix) catch "unknown";
        writer.write(kind.title());
        writer.print("Captured at {s} (unix={d})\n", .{ timestamp, unix });
        if (signal_value) |value| {
            if (comptime os.signals_supported) {
                writer.print("Signal: {s} ({d})\n", .{ report.signalLabel(value), @intFromEnum(os.toPosixSignal(value)) });
            } else {
                writer.print("Signal: {s}\n", .{report.signalLabel(value)});
            }
            writer.print("Signal code: {d}\n", .{signal_code});
            if (fault_address) |address| {
                writer.print("Fault address: 0x{x}\n", .{address});
            } else {
                writer.write("Fault address: unavailable\n");
            }
        }
        writer.print("PID: {d} TID: {d}\n", .{ os.getpid(), os.gettid() });
        writer.print("Program: {s}\nHost: {s}\nUser: {s}\n", .{
            self.programSlice(),
            self.hostSlice(),
            self.userSlice(),
        });
        writer.write("Reason: ");
        writer.write(reason);
        writer.write("\n");
        if (message.len != 0) {
            writer.write("Message: ");
            writer.write(message);
            writer.write("\n");
        }
        writer.write("\nStack trace:\n");
        if (captured.return_addresses.len == 0) {
            writer.write("  (no stack frames captured)\n");
        } else {
            for (captured.return_addresses, 0..) |address, index| {
                writer.print("  #{d} 0x{x}\n", .{ index, address });
            }
        }
    }

    fn writeStderr(self: *FailureHandler, bytes: []const u8) void {
        if (!self.write_stderr) return;
        if (!os.writeStderr(bytes)) {
            if (comptime !os.posix) std.debug.print("{s}", .{bytes});
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

fn formatSymbolized(writer: *report.Writer, captured: std.debug.StackTrace) void {
    writer.write("\nSymbolized stack trace:\n");
    if (!trace.appendSymbolized(&writer.inner, &captured)) writer.truncated = true;
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
    try handler.install();
    defer handler.uninstall();
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

test "record falls back to the configured path before install" {
    if (comptime !os.posix) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var path_buffer: [report.max_path]u8 = undefined;
    const directory = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var handler = try FailureHandler.init(std.testing.io, .{
        .directory = directory,
        .program_name = "unit-fallback",
        .host_name = "unit-host",
        .user_name = "unit-user",
        .install_signal_handlers = false,
        .write_stderr = false,
        .symbolize_stack_trace = false,
    });
    try handler.record("fallback", "before install");

    var found_name: ?[128]u8 = null;
    var found_len: usize = 0;
    var iterator = tmp.dir.iterate();
    while (try iterator.next(std.testing.io)) |entry| {
        if (std.mem.indexOf(u8, entry.name, "unit-fallback.") != null) {
            var name_buffer: [128]u8 = undefined;
            @memcpy(name_buffer[0..entry.name.len], entry.name);
            found_name = name_buffer;
            found_len = entry.name.len;
        }
    }
    try std.testing.expect(found_len != 0);
    const contents = try tmp.dir.readFileAlloc(std.testing.io, found_name.?[0..found_len], std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Reason: fallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Message: before install") != null);
}
