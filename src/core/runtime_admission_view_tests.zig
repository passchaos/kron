//! Accepted records and open shared admissions protect a configuration separately.
const std = @import("std");
const Runtime = @import("runtime.zig").Runtime;
const configurations = @import("../config/routes.zig");
const MemorySink = @import("../sink/memory.zig").MemorySink;
const Sink = @import("../sink/interface.zig").Sink;

const Lease = struct {
    memory: MemorySink,
    released: usize = 0,
    fn release(raw: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.released += 1;
    }
    fn route(self: *@This(), name: []const u8) @import("runtime_types.zig").RouteOptions {
        return .{ .name = name, .sink = self.memory.sink(), .recovery_identity = name, .release = .{ .context = self, .release = release } };
    }
};

test "shared admission retains its checked view without a pending pin conversion" {
    inline for (.{ false, true }) |persistent| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_bytes: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_bytes, ".zig-cache/tmp/{s}/view.journal", .{tmp.sub_path});
        var output_bytes: [8192]u8 = undefined;
        var sink = MemorySink.initBuffer(&output_bytes);
        const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = .asynchronous,
            .memory_queue = if (persistent) null else .{ .capacity = 8, .max_record_bytes = 512 },
            .journal = if (persistent) .{ .path = path, .capacity = 8, .max_record_bytes = 512 } else null,
            .routes = &.{.{ .name = "view", .sink = sink.sink(), .recovery_identity = "view" }},
        });
        defer runtime.destroy();
        var gap = try runtime.journal.?.reserve();
        defer gap.abort();
        const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
        const view = manager.acquire();
        defer view.release();
        const before = configurations.TestingAudit.global_pending_rmw.load(.monotonic);
        const admission = switch (runtime.begin(.info, "view")) {
            .ready => |ready| ready,
            else => return error.UnexpectedAdmission,
        };
        var admitted = true;
        defer if (admitted) runtime.end();
        try std.testing.expectEqual(@as(usize, 2), view.snapshot.readers.load(.seq_cst));
        try std.testing.expectEqual(@as(usize, 0), view.snapshot.pendingCount());
        try std.testing.expectEqual(before, configurations.TestingAudit.global_pending_rmw.load(.monotonic));
        try std.testing.expectEqual(@import("runtime_types.zig").EmitResult.accepted, try runtime.submit(admission, .{ .level = .info, .scope = "view", .message = "held", .timestamp_ns = 0, .fields = &.{} }));
        try std.testing.expectEqual(@as(usize, 1), view.snapshot.pendingCount());
        runtime.end();
        admitted = false;
        try std.testing.expectEqual(@as(usize, 1), view.snapshot.readers.load(.seq_cst));
        try std.testing.expectEqual(@as(usize, 1), view.snapshot.pendingCount());
        try std.testing.expectEqual(before + 1, configurations.TestingAudit.global_pending_rmw.load(.monotonic));
        gap.abort();
        try runtime.flush(.written);
        try std.testing.expectEqual(@as(usize, 0), view.snapshot.pendingCount());
        try std.testing.expectEqual(@as(u64, 1), runtime.health().written);
    }
}

test "shared admission old view preserves retired lease before reserve and after worker acknowledgement" {
    const Replacement = struct {
        runtime: *Runtime,
        next: *Lease,
        failure: ?anyerror = null,
        collected: usize = 99,
        fn run(self: *@This()) void {
            _ = self.runtime.replaceConfiguration(&.{self.next.route("next")}, .{}) catch |err| {
                self.failure = err;
                return;
            };
            const manager: *configurations.Manager = @ptrCast(@alignCast(self.runtime.configuration_handle));
            self.collected = manager.collectRetired() catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var old_bytes: [8192]u8 = undefined;
    var next_bytes: [8192]u8 = undefined;
    var old: Lease = .{ .memory = MemorySink.initBuffer(&old_bytes) };
    var next: Lease = .{ .memory = MemorySink.initBuffer(&next_bytes) };
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 512 },
        .configuration_slots = 2,
        .routes = &.{old.route("old")},
    });
    defer runtime.destroy();
    const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
    const initial = manager.acquire();
    const snapshot = initial.snapshot;
    initial.release();
    const admission = switch (runtime.begin(.info, "held")) {
        .ready => |ready| ready,
        else => return error.UnexpectedAdmission,
    };
    var admitted = true;
    defer if (admitted) runtime.end();
    var replacement: Replacement = .{ .runtime = runtime, .next = &next };
    const thread = try std.Thread.spawn(.{}, Replacement.run, .{&replacement});
    thread.join();
    if (replacement.failure) |err| return err;
    try std.testing.expectEqual(@as(usize, 0), replacement.collected);
    try std.testing.expectEqual(@as(usize, 0), old.released);
    try std.testing.expectEqual(@as(usize, 1), snapshot.readers.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), snapshot.pendingCount());
    try std.testing.expectEqual(@import("runtime_types.zig").EmitResult.accepted, try runtime.submit(admission, .{ .level = .info, .scope = "held", .message = "old", .timestamp_ns = 0, .fields = &.{} }));
    const deadline = @import("control.zig").Deadline.after(std.testing.io, 5 * std.time.ns_per_s);
    while (runtime.health().written != 1 or snapshot.readers.load(.seq_cst) != 1) {
        if (deadline.expired(std.testing.io)) return error.WorkerDidNotWrite;
        std.atomic.spinLoopHint();
    }
    try std.testing.expectEqual(@as(usize, 0), snapshot.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), snapshot.readers.load(.seq_cst));
    // Direct owning collection has no admission cut; a reader still blocks it.
    try std.testing.expectEqual(@as(usize, 0), try manager.collectRetired());
    try std.testing.expectEqual(@as(usize, 0), old.released);
    runtime.end();
    admitted = false;
    try std.testing.expectEqual(@as(usize, 0), snapshot.readers.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 1), try runtime.collectConfigurations());
    try std.testing.expectEqual(@as(usize, 1), old.released);
    try std.testing.expectEqual(@as(usize, 1), old.memory.records);
    try std.testing.expectEqual(@as(usize, 0), next.memory.records);
}

test "shared admission view unwinds filtered sampled capture failure and sync delivery failure" {
    var bytes: [8192]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const runtime = try Runtime.create(std.testing.allocator, std.testing.io, .{
        .routes = &.{.{ .name = "out", .sink = sink.sink() }},
        .sampling = .{ .count = 0 },
    });
    defer runtime.destroy();
    const manager: *configurations.Manager = @ptrCast(@alignCast(runtime.configuration_handle));
    const view = manager.acquire();
    defer view.release();
    const pins_before = configurations.TestingAudit.global_pending_rmw.load(.monotonic);
    for (0..100) |_| {
        try std.testing.expectEqual(@import("runtime_types.zig").EmitResult.filtered, try runtime.scoped("out").tryEmit(.debug, "filtered", .{}));
        try std.testing.expectEqual(@import("runtime_types.zig").EmitResult.sampled, try runtime.scoped("out").tryEmit(.info, "sampled", .{}));
    }
    try std.testing.expectEqual(pins_before, configurations.TestingAudit.global_pending_rmw.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), view.snapshot.readers.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), view.snapshot.pendingCount());
    // Warn bypasses the exhausted sampler, enters capture, then duplicate keys
    // unwind the admission reader without leaving a record or pending pin.
    try std.testing.expectError(error.DuplicateKey, runtime.scoped("out").tryEmit(.warn, "bad", &.{ @import("field.zig").kv("same", 1), @import("field.zig").kv("same", 2) }));
    try std.testing.expectEqual(@as(usize, 1), view.snapshot.readers.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
    try std.testing.expectEqual(pins_before, configurations.TestingAudit.global_pending_rmw.load(.monotonic));
    sink.fail_after_records = 0;
    try std.testing.expectError(error.InjectedWriteFailure, runtime.scoped("out").tryEmit(.warn, "fails", .{}));
    try std.testing.expectEqual(@as(usize, 1), view.snapshot.readers.load(.seq_cst));
    try std.testing.expectEqual(@as(usize, 0), view.snapshot.pendingCount());
    try std.testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
}
