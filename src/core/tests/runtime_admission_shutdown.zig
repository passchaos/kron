//! Runtime ownership and worker wakeups around the shared shard protocol.
const std = @import("std");
const builtin = @import("builtin");
const Runtime = @import("../runtime.zig").Runtime;
const MemorySink = @import("../../sink/memory.zig").MemorySink;

fn await(event: *std.Io.Event) !void {
    try event.waitTimeout(std.testing.io, .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } });
}

const SleepingObserver = struct {
    runtime: std.atomic.Value(?*Runtime) = .init(null),
    closing_sleep: std.Io.Event = .unset,
    var current: std.atomic.Value(?*SleepingObserver) = .init(null);

    fn observe(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
        if (current.load(.acquire)) |self| if (self.runtime.load(.acquire)) |runtime| {
            if (ptr == &runtime.wake_epoch.raw and runtime.state.load(.acquire) == .closing and runtime.activeAdmissions() == 1)
                self.closing_sleep.set(std.testing.io);
        };
        std.testing.io.vtable.futexWaitUncancelable(userdata, ptr, expected);
    }
};

test "shared runtime final admission wakes sleeping closing worker without submitting a record" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const Producer = struct {
        runtime: *Runtime,
        held: std.Io.Event = .unset,
        finish: std.Io.Event = .unset,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            switch (self.runtime.begin(.info, "shared.final")) {
                .ready => {},
                else => {
                    self.failure = error.UnexpectedAdmission;
                    self.held.set(std.testing.io);
                    return;
                },
            }
            defer self.runtime.end();
            self.held.set(std.testing.io);
            self.finish.waitUncancelable(std.testing.io);
        }
    };
    const Shutdown = struct {
        runtime: *Runtime,
        done: std.Io.Event = .unset,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            defer self.done.set(std.testing.io);
            self.runtime.shutdown(.drain) catch |err| {
                self.failure = err;
            };
        }
    };
    var observer: SleepingObserver = .{};
    SleepingObserver.current.store(&observer, .release);
    defer SleepingObserver.current.store(null, .release);
    var vtable = std.testing.io.vtable.*;
    vtable.futexWaitUncancelable = SleepingObserver.observe;
    const io: std.Io = .{ .userdata = std.testing.io.userdata, .vtable = &vtable };
    var storage: [4096]u8 = undefined;
    var memory = MemorySink.initBuffer(&storage);
    const runtime = try Runtime.create(std.testing.allocator, io, .{
        .submission = .asynchronous,
        .idle = .sleep,
        .memory_queue = .{ .capacity = 2, .max_record_bytes = 512 },
        .routes = &.{.{ .name = "memory", .sink = memory.sink() }},
    });
    defer runtime.destroy();
    observer.runtime.store(runtime, .release);
    var producer: Producer = .{ .runtime = runtime };
    const producing = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    var shutting: ?std.Thread = null;
    defer {
        producer.finish.set(std.testing.io);
        producing.join();
        if (shutting) |thread| {
            // Make a failed assertion clean up instead of stranding a sleeper.
            runtime.stopAccepting() catch {};
            thread.join();
        }
    }
    try await(&producer.held);
    if (producer.failure) |err| return err;
    try std.testing.expectEqual(@as(u64, 1), runtime.activeAdmissions());
    var shutdown: Shutdown = .{ .runtime = runtime };
    shutting = try std.Thread.spawn(.{}, Shutdown.run, .{&shutdown});
    try await(&observer.closing_sleep);
    try std.testing.expect(!shutdown.done.isSet());
    producer.finish.set(std.testing.io);
    try await(&shutdown.done);
    if (shutdown.failure) |err| return err;
    try std.testing.expectEqual(@as(u64, 0), runtime.activeAdmissions());
    try std.testing.expectEqual(@as(usize, 0), memory.records);
    try std.testing.expectEqual(.closed, runtime.health().state);
}
