//! Deadline behavior through the public consumer API and real sink callbacks.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const testing = std.testing;
const Atomic = std.atomic.Value;
const short_ns = 10 * std.time.ns_per_ms;
const test_ns = 5 * std.time.ns_per_s;

fn wait(event: *std.Io.Event) !void {
    const deadline = kron.Deadline.after(testing.io, test_ns);
    while (!event.isSet()) event.waitTimeout(testing.io, .{ .deadline = deadline.timestamp }) catch |err| {
        if (err != error.Timeout) return err;
        if (deadline.expired(testing.io) and !event.isSet()) return error.TestHandshakeTimeout;
    };
}

fn pathFor(tmp: *const testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/deadline.journal", .{tmp.sub_path});
}

const BlockingSink = struct {
    memory: kron.MemorySink,
    block_flush: Atomic(bool) = .init(false),
    block_sync: Atomic(bool) = .init(false),
    flush_calls: Atomic(u64) = .init(0),
    sync_calls: Atomic(u64) = .init(0),
    entered: std.Io.Event = .unset,
    release_event: std.Io.Event = .unset,
    return_error: ?anyerror = null,

    fn cast(context: *anyopaque) *BlockingSink {
        return @ptrCast(@alignCast(context));
    }
    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        try cast(context).memory.writeRecord(record);
    }
    fn flush(context: *anyopaque) anyerror!void {
        const self = cast(context);
        _ = self.flush_calls.fetchAdd(1, .monotonic);
        if (self.block_flush.swap(false, .acq_rel)) try self.block();
        try self.memory.flush();
        if (self.return_error) |err| return err;
    }
    fn sync(context: *anyopaque) anyerror!void {
        const self = cast(context);
        _ = self.sync_calls.fetchAdd(1, .monotonic);
        if (self.block_sync.swap(false, .acq_rel)) try self.block();
    }
    fn block(self: *BlockingSink) !void {
        self.entered.set(testing.io);
        try wait(&self.release_event);
    }
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
    fn sink(self: *BlockingSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable, .supports_durable = true, .recovery_identity = "deadline-test-sink" };
    }
};

test "external deadline: timed written flush and durable sync detach while accepted records stay owned" {
    inline for (.{ false, true }) |durable| {
        var bytes: [8192]u8 = undefined;
        var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .routes = &.{.{ .name = "required", .sink = sink.sink() }},
        });
        defer runtime.destroy();
        defer sink.release_event.set(testing.io);
        const log = runtime.scoped("deadline.flush");
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "accepted before timeout", .{ .id = 1 }));
        const before = runtime.controlStatus().completed_operations;
        if (durable) sink.block_sync.store(true, .release) else sink.block_flush.store(true, .release);
        try testing.expectError(error.Timeout, runtime.flushUntil(if (durable) .durable else .written, kron.Deadline.after(testing.io, short_ns)));
        try wait(&sink.entered);
        const status = runtime.controlStatus();
        try testing.expect(status.busy and status.detached);
        try testing.expectEqual(before, status.completed_operations);
        try testing.expectEqual(@as(u64, 1), status.timed_out_operations);
        try testing.expectEqual(.running, runtime.health().state);
        try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
        try testing.expect(log.enabled(.info));
        sink.release_event.set(testing.io);
        try runtime.flushUntil(if (durable) .durable else .written, kron.Deadline.after(testing.io, test_ns));
        try testing.expect(!runtime.controlStatus().busy);
        try testing.expect(!runtime.controlStatus().detached);
        try testing.expectEqual(before + 2, runtime.controlStatus().completed_operations);
        try testing.expectEqual(@as(usize, 1), sink.memory.records);
        try testing.expect(std.mem.indexOf(u8, sink.memory.written(), "accepted before timeout") != null);
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "accepted after retry", .{ .id = 2 }));
        try runtime.shutdownUntil(kron.Deadline.after(testing.io, test_ns));
        try testing.expectEqual(@as(usize, 2), sink.memory.records);
        try testing.expectEqual(@as(u64, 2), runtime.health().written);
    }
}

test "external deadline: named route flush copies selection before a caller timeout" {
    var selected_bytes: [4096]u8 = undefined;
    var other_bytes: [4096]u8 = undefined;
    var selected: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&selected_bytes) };
    var other: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&other_bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{
            .{ .name = "selected", .sink = selected.sink() },
            .{ .name = "other", .sink = other.sink() },
        },
    });
    defer runtime.destroy();
    defer selected.release_event.set(testing.io);
    var name = "selected".*;
    var names = [_][]const u8{name[0..]};
    selected.block_flush.store(true, .release);
    try testing.expectError(error.Timeout, runtime.flushRoutesUntil(&names, .written, kron.Deadline.after(testing.io, short_ns)));
    try wait(&selected.entered);
    @memset(&name, 'x');
    names[0] = "other";
    try testing.expectEqual(@as(u64, 0), other.flush_calls.load(.acquire));
    selected.release_event.set(testing.io);
    try runtime.flushRoutesUntil(&.{"selected"}, .written, kron.Deadline.after(testing.io, test_ns));
    try testing.expectEqual(@as(u64, 2), selected.flush_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 0), other.flush_calls.load(.acquire));
}

test "external deadline: timed shutdown keeps closing until a blocked sink finishes" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    inline for (.{ .sync, .asynchronous }) |submission| {
        var tmp = testing.tmpDir(.{});
        defer tmp.cleanup();
        var path_buffer: [128]u8 = undefined;
        var bytes: [8192]u8 = undefined;
        var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
        const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
            .submission = submission,
            .journal = if (submission == .asynchronous) .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 1024 } else null,
            .routes = &.{.{ .name = "required", .sink = sink.sink() }},
        });
        defer runtime.destroy();
        defer sink.release_event.set(testing.io);
        const log = runtime.scoped("deadline.shutdown");
        try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "shutdown retains acceptance", .{}));
        try runtime.flush(.written);
        sink.block_flush.store(true, .release);
        try testing.expectError(error.Timeout, runtime.shutdownUntil(kron.Deadline.after(testing.io, short_ns)));
        try wait(&sink.entered);
        try testing.expectEqual(.closing, runtime.health().state);
        try testing.expect(runtime.controlStatus().busy and runtime.controlStatus().detached);
        try testing.expectEqual(kron.EmitResult.rejected_closing, try log.tryEmit(.fatal, "closed admission", .{}));
        sink.release_event.set(testing.io);
        try runtime.shutdownUntil(kron.Deadline.after(testing.io, test_ns));
        try testing.expectEqual(.closed, runtime.health().state);
        try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
        try testing.expectEqual(@as(u64, 1), runtime.health().written);
        try testing.expectEqual(@as(usize, 1), sink.memory.records);
        try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
        try testing.expect(!runtime.controlStatus().busy);
    }
}

test "external deadline: an already expired call starts no callback and leaves admission open" {
    var bytes: [4096]u8 = undefined;
    var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    const expired = kron.Deadline.after(testing.io, 0);
    try testing.expectError(error.Timeout, runtime.flushUntil(.written, expired));
    try testing.expectError(error.Timeout, runtime.flushRoutesUntil(&.{"required"}, .durable, expired));
    try testing.expectError(error.Timeout, runtime.shutdownUntil(expired));
    try testing.expectEqual(@as(u64, 0), sink.flush_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 0), sink.sync_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 0), runtime.controlStatus().completed_operations);
    try testing.expect(!runtime.controlStatus().busy);
    try testing.expectEqual(.running, runtime.health().state);
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("expired").tryEmit(.info, "still open", .{}));
}

test "external deadline: closed shutdown repeats its latched final flush error" {
    var bytes: [4096]u8 = undefined;
    var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("deadline.shutdown.failure");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "accepted before final flush failure", .{}));
    sink.return_error = error.InjectedDeadlineFailure;
    try testing.expectError(error.InjectedDeadlineFailure, runtime.shutdownUntil(kron.Deadline.after(testing.io, test_ns)));
    try testing.expectEqual(.closed, runtime.health().state);
    const flush_calls = sink.flush_calls.load(.acquire);
    try testing.expectError(error.InjectedDeadlineFailure, runtime.shutdownUntil(kron.Deadline.after(testing.io, test_ns)));
    try testing.expectError(error.InjectedDeadlineFailure, runtime.shutdown(.drain));
    try testing.expectEqual(flush_calls, sink.flush_calls.load(.acquire));
    try testing.expectEqual(error.InjectedDeadlineFailure, runtime.controlStatus().last_error.?);
    try testing.expectEqual(kron.EmitResult.rejected_closing, try log.tryEmit(.fatal, "after failed shutdown", .{}));
    try testing.expectEqual(@as(u64, 1), runtime.health().accepted);
    try testing.expectEqual(@as(usize, 1), sink.memory.records);
}

test "external deadline: waiting for the occupied control slot consumes the second caller deadline" {
    var first_bytes: [4096]u8 = undefined;
    var second_bytes: [4096]u8 = undefined;
    var first: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&first_bytes) };
    var second: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&second_bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{
            .{ .name = "first", .sink = first.sink() },
            .{ .name = "second", .sink = second.sink() },
        },
    });
    defer runtime.destroy();
    defer first.release_event.set(testing.io);
    first.block_flush.store(true, .release);
    try testing.expectError(error.Timeout, runtime.flushRoutesUntil(&.{"first"}, .written, kron.Deadline.after(testing.io, short_ns)));
    try wait(&first.entered);
    try testing.expectError(error.Timeout, runtime.flushRoutesUntil(&.{"second"}, .written, kron.Deadline.after(testing.io, short_ns)));
    try testing.expectEqual(@as(u64, 0), second.flush_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 0), runtime.controlStatus().completed_operations);
    try testing.expect(runtime.controlStatus().busy and runtime.controlStatus().detached);
    first.release_event.set(testing.io);
    try runtime.flushRoutesUntil(&.{"second"}, .written, kron.Deadline.after(testing.io, test_ns));
    try testing.expectEqual(@as(u64, 1), first.flush_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 1), second.flush_calls.load(.acquire));
    try testing.expectEqual(@as(u64, 2), runtime.controlStatus().completed_operations);
}

test "external deadline: detached callback failure stays inspectable and a later call succeeds" {
    var bytes: [4096]u8 = undefined;
    var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes), .return_error = error.InjectedDeadlineFailure };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    defer sink.release_event.set(testing.io);
    sink.block_flush.store(true, .release);
    try testing.expectError(error.Timeout, runtime.flushUntil(.written, kron.Deadline.after(testing.io, short_ns)));
    try wait(&sink.entered);
    sink.release_event.set(testing.io);
    try testing.expectError(error.InjectedDeadlineFailure, runtime.flushUntil(.written, kron.Deadline.after(testing.io, test_ns)));
    try testing.expectEqual(error.InjectedDeadlineFailure, runtime.health().last_error.?);
    try testing.expectEqual(error.InjectedDeadlineFailure, runtime.controlStatus().last_error.?);
    try testing.expectEqual(@as(u64, 2), runtime.controlStatus().completed_operations);
    try testing.expect(!runtime.controlStatus().busy);
    sink.return_error = null;
    try runtime.flushUntil(.written, kron.Deadline.after(testing.io, test_ns));
}

fn assertReentrant(runtime: *kron.Runtime, expected: anyerror) !void {
    const deadline = kron.Deadline.after(testing.io, short_ns);
    try testing.expectError(expected, runtime.flushUntil(.written, deadline));
    try testing.expectError(expected, runtime.flushRoutesUntil(&.{"required"}, .written, deadline));
    try testing.expectError(expected, runtime.shutdownUntil(deadline));
}

test "external deadline: producer admission rejects all three timed control APIs" {
    var bytes: [4096]u8 = undefined;
    var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    const admission = runtime.begin(.info, "deadline.producer").ready;
    defer runtime.end();
    try assertReentrant(runtime, error.ProducerReentrant);
    try testing.expectEqual(.running, runtime.health().state);
    try testing.expectEqual(@as(u64, 0), runtime.controlStatus().completed_operations);
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.submit(admission, .{
        .level = .info,
        .scope = "deadline.producer",
        .message = "rejected control leaves admission usable",
        .fields = &.{},
        .timestamp_ns = 1,
    }));
}

const ReentrantSink = struct {
    runtime: ?*kron.Runtime = null,
    memory: kron.MemorySink,
    worker_checks: Atomic(u64) = .init(0),
    control_checks: Atomic(u64) = .init(0),
    probe_control: Atomic(bool) = .init(false),
    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        const self: *ReentrantSink = @ptrCast(@alignCast(context));
        try assertReentrant(self.runtime.?, error.WorkerReentrant);
        _ = self.worker_checks.fetchAdd(1, .release);
        try self.memory.writeRecord(record);
    }
    fn flush(context: *anyopaque) anyerror!void {
        const self: *ReentrantSink = @ptrCast(@alignCast(context));
        if (self.probe_control.swap(false, .acq_rel)) {
            try assertReentrant(self.runtime.?, error.ControlReentrant);
            _ = self.control_checks.fetchAdd(1, .release);
        }
    }
    fn sync(_: *anyopaque) anyerror!void {}
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = sync };
    fn sink(self: *ReentrantSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable, .recovery_identity = "deadline-reentrant" };
    }
};

test "external deadline: collector and control sink callbacks reject timed reentry" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var bytes: [4096]u8 = undefined;
    var sink: ReentrantSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try pathFor(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 1024 },
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    sink.runtime = runtime;
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("deadline.worker").tryEmit(.info, "worker rejects reentry", .{}));
    try runtime.flush(.written);
    try testing.expectEqual(@as(u64, 1), sink.worker_checks.load(.acquire));
    sink.probe_control.store(true, .release);
    try runtime.flushUntil(.written, kron.Deadline.after(testing.io, test_ns));
    try testing.expectEqual(@as(u64, 1), sink.control_checks.load(.acquire));
    try testing.expectEqual(@as(u64, 1), runtime.health().written);
}

const ReentrantHook = struct {
    runtime: ?*kron.Runtime = null,
    calls: usize = 0,
    failure: ?anyerror = null,
    fn invoke(context: ?*anyopaque, _: kron.diagnostics.ErrorEvent) void {
        const self: *ReentrantHook = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        assertReentrant(self.runtime.?, error.DiagnosticReentrant) catch |err| {
            self.failure = err;
        };
    }
};

test "external deadline: diagnostic hooks reject timed control without closing admission" {
    var bytes: [4096]u8 = undefined;
    var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    var hook: ReentrantHook = .{};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
        .diagnostics = .{ .hook = ReentrantHook.invoke, .context = &hook },
    });
    defer runtime.destroy();
    hook.runtime = runtime;
    runtime.reportError(error.TriggerDeadlineHook);
    if (hook.failure) |err| return err;
    try testing.expectEqual(@as(usize, 1), hook.calls);
    try testing.expectEqual(@as(u64, 0), runtime.controlStatus().completed_operations);
    try testing.expectEqual(.running, runtime.health().state);
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("deadline.hook").tryEmit(.info, "still running", .{}));
}

test "external deadline: timed detachment retry and shutdown allocate nothing after initialization" {
    var bytes: [8192]u8 = undefined;
    var sink: BlockingSink = .{ .memory = kron.MemorySink.initBuffer(&bytes) };
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{
        .routes = &.{.{ .name = "required", .sink = sink.sink() }},
    });
    defer runtime.destroy();
    defer sink.release_event.set(testing.io);
    const initialized = failing.alloc_index;
    failing.fail_index = initialized;
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("deadline.allocations").tryEmit(.info, "allocated during init", .{}));
    sink.block_flush.store(true, .release);
    try testing.expectError(error.Timeout, runtime.flushUntil(.written, kron.Deadline.after(testing.io, short_ns)));
    try wait(&sink.entered);
    try testing.expect(runtime.controlStatus().detached);
    sink.release_event.set(testing.io);
    try runtime.flushRoutesUntil(&.{"required"}, .durable, kron.Deadline.after(testing.io, test_ns));
    try runtime.shutdownUntil(kron.Deadline.after(testing.io, test_ns));
    try testing.expectEqual(initialized, failing.alloc_index);
    try testing.expect(!failing.has_induced_failure);
    try testing.expectEqual(@as(usize, 1), sink.memory.records);
}
