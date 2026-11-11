//! Demonstrates glog-style failure capture.
//!
//! The default run installs the handler, emits a normal log, and writes one
//! non-fatal crash report. Use `--crash segv|fatal|fatal-log` to terminate the
//! process so the handler captures a real signal or fatal event:
//!
//!     zig build run-failure-handler -- --crash segv
//!     zig build run-failure-handler -- --crash fatal
//!     zig build run-failure-handler -- --crash fatal-log
const std = @import("std");
const kron = @import("kron");

const CrashMode = enum { none, segv, fatal, @"fatal-log" };

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    var directory: []const u8 = ".zig-cache/examples/failure-handler";
    var crash: CrashMode = .none;
    var index: usize = 1;
    while (index < arguments.len) : (index += 1) {
        if (std.mem.eql(u8, arguments[index], "--directory") and index + 1 < arguments.len) {
            index += 1;
            directory = arguments[index];
        } else if (std.mem.eql(u8, arguments[index], "--crash") and index + 1 < arguments.len) {
            index += 1;
            crash = std.meta.stringToEnum(CrashMode, arguments[index]) orelse return error.InvalidCrashMode;
        } else return error.InvalidArguments;
    }

    var failure = try kron.FailureHandler.init(init.io, .{
        .directory = directory,
        .program_name = "kron-failure-example",
        .write_stderr = true,
        .max_stack_frames = 32,
        // Bind `.fatal` events to the handler for the fatal-log demo.
        .abort_on_fatal = true,
    });
    try failure.install();
    defer failure.uninstall();

    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{.{
            .name = "stdout",
            .target = .stdout,
            .format = .text,
            .filter = "info",
        }},
        .failure_handler = &failure,
    });
    defer logging.destroy();

    const log = logging.scoped("failure.example");
    log.info("failure handler installed", .{ .crash_directory = directory, .crash_mode = @tagName(crash) });

    switch (crash) {
        .none => {
            try failure.record("example", "non-fatal diagnostic report");
            print(init.io, "latest report: {s}/kron-failure-example.FATAL\n", .{directory});
            print(init.io, "rerun with --crash segv|fatal|fatal-log to capture a terminating crash\n", .{});
            try logging.flush();
            try logging.shutdown();
        },
        .segv => {
            try logging.flush();
            // A real invalid access: the handler writes the report and then
            // re-raises SIGSEGV, so the shell observes the original signal.
            const invalid: *allowzero volatile u8 = @ptrFromInt(@as(usize, 0));
            invalid.* = 1;
            std.process.exit(1);
        },
        .fatal => {
            try logging.flush();
            failure.fatal("example fatal crash");
        },
        .@"fatal-log" => {
            log.fatal("example fatal event", .{ .request_id = @as(u64, 42) });
            std.process.exit(1);
        },
    }
}

fn print(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buffer: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, fmt, args) catch return;
    std.Io.File.stdout().writeStreamingAll(io, text) catch {};
}
