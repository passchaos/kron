//! Child workload for tests/failure_handler.py.
//!
//! Every mode installs a real failure handler. Signal and fatal modes are
//! expected to terminate by signal; `record` writes one report and exits 0.
const std = @import("std");
const kron = @import("kron");

const Mode = enum { record, fatal, @"fatal-log", segv, @"segv-chdir", @"segv-raw", @"stack-overflow", @"thread-segv", abort, term };

fn chdirRoot() void {
    if (comptime @import("builtin").os.tag == .linux) {
        _ = std.os.linux.chdir("/");
    }
}

noinline fn recurse(depth: usize) void {
    var pad: [4096]u8 = undefined;
    @memset(&pad, @truncate(depth));
    recurse(depth + 1);
    std.mem.doNotOptimizeAway(&pad);
}

const ThreadWorker = struct {
    fn run() void {
        const invalid: *allowzero volatile u8 = @ptrFromInt(@as(usize, 0));
        invalid.* = 1;
    }
};

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    var directory: ?[]const u8 = null;
    var mode: ?Mode = null;
    var index: usize = 1;
    while (index < arguments.len) : (index += 1) {
        if (std.mem.eql(u8, arguments[index], "--directory") and index + 1 < arguments.len) {
            index += 1;
            directory = arguments[index];
        } else if (std.mem.eql(u8, arguments[index], "--mode") and index + 1 < arguments.len) {
            index += 1;
            mode = std.meta.stringToEnum(Mode, arguments[index]) orelse return error.InvalidMode;
        } else return error.InvalidArguments;
    }
    const selected = mode orelse return error.ModeRequired;
    const crash_directory = directory orelse return error.DirectoryRequired;

    var handler = try kron.FailureHandler.init(init.io, .{
        .directory = crash_directory,
        .program_name = "kron-failure-writer",
        .host_name = "test-host",
        .user_name = "test-user",
        .install_signal_handlers = selected != .record,
        .write_stderr = true,
        .symbolize_signal_stack_trace = selected != .@"segv-raw",
        .max_stack_frames = 16,
        .abort_on_fatal = selected == .@"fatal-log",
    });
    try handler.install();
    defer handler.uninstall();

    switch (selected) {
        .record => {
            try handler.record("diagnostic", "record message");
        },
        .fatal => handler.fatal("intentional fatal message"),
        .@"fatal-log" => {
            var output: [4096]u8 = undefined;
            var writer = std.Io.Writer.fixed(&output);
            const logging = try kron.Logging.create(init.gpa, init.io, .{
                .outputs = &.{.{
                    .name = "failure-test",
                    .target = .{ .writer = &writer },
                    .format = .json,
                    .filter = "info",
                }},
                .failure_handler = &handler,
            });
            defer logging.destroy();
            logging.scoped("failure.test").fatal("fatal log message", .{ .id = @as(u32, 7) });
            return error.FatalLogDidNotAbort;
        },
        .segv => {
            const invalid: *allowzero volatile u8 = @ptrFromInt(@as(usize, 0));
            invalid.* = 1;
            std.process.exit(1);
        },
        .@"segv-chdir" => {
            // The crash directory was opened during install; changing the
            // process working directory must not redirect or break the report.
            chdirRoot();
            const invalid: *allowzero volatile u8 = @ptrFromInt(@as(usize, 0));
            invalid.* = 1;
            std.process.exit(1);
        },
        .@"segv-raw" => {
            const invalid: *allowzero volatile u8 = @ptrFromInt(@as(usize, 0));
            invalid.* = 1;
            std.process.exit(1);
        },
        .@"stack-overflow" => {
            recurse(0);
            std.process.exit(1);
        },
        .@"thread-segv" => {
            const thread = try std.Thread.spawn(.{}, ThreadWorker.run, .{});
            thread.join();
            std.process.exit(1);
        },
        .abort => {
            std.posix.raise(.ABRT) catch std.process.abort();
            std.process.exit(1);
        },
        .term => {
            std.posix.raise(.TERM) catch std.process.abort();
            std.process.exit(1);
        },
    }
}
