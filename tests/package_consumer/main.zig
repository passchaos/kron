//! An ordinary Zig application which imports kron through b.dependency.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
pub const platform_host = @import("platform.zig");

pub const Mode = enum { sync, memory, mmap, spsc_memory, spsc_mmap };

pub fn parseMode(text: []const u8) !Mode {
    return std.meta.stringToEnum(Mode, text) orelse error.InvalidMode;
}

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len != 3) return error.ExpectedModeAndDirectory;
    if (std.mem.eql(u8, arguments[1], "qualify")) {
        const report = try platform_host.run(init.gpa, init.io, arguments[2]);
        var bytes: [4096]u8 = undefined;
        var output = std.Io.File.stdout().writerStreaming(init.io, &bytes);
        try std.json.Stringify.value(report, .{}, &output.interface);
        try output.interface.writeByte('\n');
        try output.interface.flush();
        return;
    }
    const mode = try parseMode(arguments[1]);
    try run(init.gpa, init.io, mode, arguments[2]);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, mode: Mode, directory: []const u8) !void {
    if (builtin.single_threaded and mode != .sync) return error.ThreadsUnavailable;
    const dir = try std.Io.Dir.cwd().createDirPathOpen(io, directory, .{ .open_options = .{ .iterate = true } });
    defer dir.close(io);
    const journal_path = try std.fs.path.join(allocator, &.{ directory, "events.journal" });
    defer allocator.free(journal_path);
    const attached = mode == .spsc_memory or mode == .spsc_mmap;
    const mapped = mode == .mmap or mode == .spsc_mmap;
    const memory = mode == .memory or mode == .spsc_memory;
    const logging = try kron.Logging.create(allocator, io, .{
        .output = .{ .file = .{ .dir = dir, .path = "events.jsonl", .backend = .portable } },
        .format = .json,
        .mode = if (mode == .sync) .sync else if (attached) .spsc else .asynchronous,
        .queue = if (memory) .{ .memory = .{ .capacity = 16, .max_record_bytes = 4096 } } else if (mapped) .{ .mmap = .{ .path = journal_path, .capacity = 16, .max_record_bytes = 4096 } } else null,
        .max_threads = 1,
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer logging.destroy();
    const runtime = logging.runtime();
    if (attached) {
        const log = try logging.attachThread("consumer");
        defer log.detach() catch {};
        try events(runtime, log);
    } else try events(runtime, logging.scoped("consumer"));
    try logging.flush();
    try logging.shutdown();
    const health = logging.health();
    var thread_count: ?usize = null;
    if (builtin.single_threaded) {
        if (runtime.controlStatus().available or health.worker_alive) return error.UnexpectedBackgroundThread;
        if (comptime builtin.os.tag == .linux) {
            const task_directory = try std.Io.Dir.openDirAbsolute(io, "/proc/self/task", .{ .iterate = true });
            defer task_directory.close(io);
            var iterator = task_directory.iterate();
            var count: usize = 0;
            while (try iterator.next(io)) |_| count += 1;
            if (count != 1) return error.UnexpectedBackgroundThread;
            thread_count = count;
        }
    }
    if (health.accepted != 2 or health.written != 2 or health.journal_pending != 0) return error.IncompleteDelivery;
    const expected_storage: kron.QueueStorage = if (mode == .sync) .none else if (memory) .memory else .mmap;
    if (runtime.queueStorage() != expected_storage) return error.WrongStorage;
    var output_bytes: [1024]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &output_bytes);
    try std.json.Stringify.value(.{
        .mode = @tagName(mode),
        .target = @tagName(kron.platform.target),
        .accepted = health.accepted,
        .written = health.written,
        .pending = health.journal_pending,
        .storage = @tagName(health.queue_storage),
        .queue_bytes = health.queue_reserved_bytes,
        .mapped_bytes = health.journal_reserved_bytes,
        .single_threaded = builtin.single_threaded,
        .thread_count = thread_count,
    }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

fn events(runtime: *kron.Runtime, base: anytype) !void {
    var name = "original".*;
    var values = [_]kron.Value{ kron.fields.fromAny(@as([]const u8, &name)), kron.fields.fromAny(kron.secret("never captured")) };
    const log = base.withBorrowed(.{ .service = "package-consumer" });
    if (try log.tryEmit(.info, "first", .{ .id = @as(u64, 1), .nested = kron.array(&values), .password = "private" }) != .accepted) return error.FirstRejected;
    // These bytes are borrowed by the call only, including ordinary memory async.
    @memset(&name, 'x');
    values = @splat(.null_value);
    try runtime.reloadFilter("off,consumer=debug");
    if (try log.tryLogf(.debug, "second {d}", .{@as(u64, 7)}, .{ .id = @as(u64, 2), .password = "private" }) != .accepted) return error.SecondRejected;
}
