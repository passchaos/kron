const std = @import("std");
const RollingFileSink = @import("rolling_file.zig").RollingFileSink;
const Clock = @import("../platform/clock.zig").Clock;
const testing = std.testing;

const FakeClock = struct {
    now: u64,
    calls: usize = 0,

    fn read(context: ?*anyopaque, _: std.Io) u64 {
        const self: *FakeClock = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        return self.now;
    }

    fn clock(self: *FakeClock) Clock {
        return .{ .context = self, .monotonic_now = read };
    }
};

fn create(dir: std.Io.Dir, clock: *FakeClock, max_bytes: u64, interval: ?u64) !*RollingFileSink {
    return RollingFileSink.create(testing.allocator, testing.io, .{
        .path = "output.log",
        .dir = dir,
        .max_bytes = max_bytes,
        .retention = 2,
        .buffer_bytes = 32,
        .backend = .portable,
        .rotation_interval_ns = interval,
        .clock = clock.clock(),
    });
}

fn expectFile(dir: std.Io.Dir, path: []const u8, expected: []const u8) !void {
    const bytes = try dir.readFileAlloc(testing.io, path, testing.allocator, .limited(128));
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings(expected, bytes);
}

test "timed rolling validates intervals and size-only mode never reads the clock" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    try testing.expectError(error.InvalidRollingOptions, create(tmp.dir, &clock, 8, 0));
    const output = try create(tmp.dir, &clock, 8, null);
    defer output.deinit();
    try output.writeRecord("one\n");
    clock.now = std.math.maxInt(u64);
    try output.writeRecord("two\n");
    try output.writeRecord("three\n");
    try output.reopen();
    try output.flush();
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
    try testing.expectEqual(@as(usize, 0), clock.calls);
    try testing.expect(output.rotation_deadline_ns == null);
    try expectFile(tmp.dir, "output.log.1", "one\ntwo\n");
}

test "timed rolling rotates exactly at the threshold and preserves whole records" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try create(tmp.dir, &clock, 32, 10);
    defer output.deinit();
    const identity = output.sink().recovery_identity.?;
    try output.writeRecord("one\n");
    clock.now = 109;
    try output.writeRecord("two\n");
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    clock.now = 110;
    try output.writeRecord("three\n");
    try output.writeRecord("four\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
    try testing.expectEqual(@as(?u64, 120), output.rotation_deadline_ns);
    try testing.expect(identity.ptr == output.sink().recovery_identity.?.ptr);
    try expectFile(tmp.dir, "output.log.1", "one\ntwo\n");
    try expectFile(tmp.dir, "output.log", "three\nfour\n");
}

test "timed rolling empty files and empty records do not create empty archives" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try create(tmp.dir, &clock, 32, 10);
    defer output.deinit();
    clock.now = 1000;
    try output.writeRecord("");
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    try testing.expectEqual(@as(usize, 1), clock.calls);
    try output.writeRecord("one\n");
    try testing.expectEqual(@as(?u64, 1010), output.rotation_deadline_ns);
    clock.now = 1010;
    try output.writeRecord("");
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    try output.writeRecord("two\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
    try expectFile(tmp.dir, "output.log.1", "one\n");
    try expectFile(tmp.dir, "output.log", "two\n");
}

test "timed rolling size and time trigger only one rotation and reset together" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try create(tmp.dir, &clock, 8, 10);
    defer output.deinit();
    try output.writeRecord("one\n");
    clock.now = 105;
    try output.writeRecord("two\n");
    clock.now = 110;
    try output.writeRecord("three\n");
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
    clock.now = 111;
    try output.writeRecord("four\n"); // size forces rollover before the deadline.
    try testing.expectEqual(@as(usize, 2), output.rollover_count);
    try testing.expectEqual(@as(?u64, 121), output.rotation_deadline_ns);
    clock.now = 120;
    try output.writeRecord("x\n");
    try testing.expectEqual(@as(usize, 2), output.rollover_count);
    clock.now = 121;
    try output.writeRecord("y\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 3), output.rollover_count);
    try expectFile(tmp.dir, "output.log.1", "four\nx\n");
    try expectFile(tmp.dir, "output.log.2", "three\n");
    try expectFile(tmp.dir, "output.log", "y\n");
}

test "timed rolling ignores backwards clocks and saturated deadlines never fire early" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try create(tmp.dir, &clock, 32, 10);
    defer output.deinit();
    try output.writeRecord("one\n");
    clock.now = 109;
    try output.writeRecord("two\n");
    clock.now = 1;
    try output.writeRecord("x\n");
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    try testing.expectEqual(@as(?u64, 110), output.rotation_deadline_ns);
    clock.now = 110;
    try output.writeRecord("y\n");
    try testing.expectEqual(@as(usize, 1), output.rollover_count);

    clock.now = std.math.maxInt(u64) - 5;
    try output.reopen();
    try testing.expectEqual(@as(?u64, std.math.maxInt(u64)), output.rotation_deadline_ns);
    clock.now = std.math.maxInt(u64);
    try output.writeRecord("z\n");
    try output.writeRecord("z\n");
    try testing.expectEqual(@as(usize, 1), output.rollover_count);

    try tmp.dir.createDir(testing.io, "exact", .default_dir);
    const exact_dir = try tmp.dir.openDir(testing.io, "exact", .{});
    defer exact_dir.close(testing.io);
    clock.now = std.math.maxInt(u64) - 10;
    const exact = try create(exact_dir, &clock, 32, 10);
    defer exact.deinit();
    try exact.writeRecord("one\n");
    clock.now = std.math.maxInt(u64);
    try exact.writeRecord("two\n");
    try exact.writeRecord("x\n");
    try testing.expectEqual(@as(usize, 1), exact.rollover_count);
}

test "timed rolling reopen and restart reset the epoch without recovering mtime" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try create(tmp.dir, &clock, 32, 10);
    try output.writeRecord("one\n");
    clock.now = 109;
    try tmp.dir.rename("output.log", tmp.dir, "external.log", testing.io);
    try output.reopen();
    try testing.expectEqual(@as(?u64, 119), output.rotation_deadline_ns);
    clock.now = 110;
    try output.writeRecord("two\n");
    try testing.expectEqual(@as(?u64, 120), output.rotation_deadline_ns);
    clock.now = 119;
    try output.writeRecord("x\n");
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    try output.flush();
    output.deinit();
    clock.now = 1000;
    const restarted = try create(tmp.dir, &clock, 32, 10);
    defer restarted.deinit();
    try testing.expectEqual(@as(?u64, 1010), restarted.rotation_deadline_ns);
    clock.now = 1009;
    try restarted.writeRecord("y\n");
    try testing.expectEqual(@as(usize, 0), restarted.rollover_count);
    clock.now = 1010;
    try restarted.writeRecord("z\n");
    try restarted.flush();
    try testing.expectEqual(@as(usize, 1), restarted.rollover_count);
    try expectFile(tmp.dir, "external.log", "one\n");
    try expectFile(tmp.dir, "output.log.1", "two\nx\ny\n");
    try expectFile(tmp.dir, "output.log", "z\n");
}

test "timed rolling failed rotations latch and reject the triggering record" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try create(tmp.dir, &clock, 32, 10);
    defer output.deinit();
    try output.writeRecord("one\n");
    try tmp.dir.createDir(testing.io, "output.log.2", .default_dir);
    clock.now = 110;
    if (output.writeRecord("two\n")) |_| return error.TestExpectedError else |_| {}
    try testing.expect(output.failure != null);
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    try testing.expectEqual(@as(?u64, 110), output.rotation_deadline_ns);
    if (output.writeRecord("x\n")) |_| return error.TestExpectedError else |_| {}
    try expectFile(tmp.dir, "output.log", "one\n");
}

test "timed rolling ordinary record checks allocate nothing after initialization" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const output = try RollingFileSink.create(failing.allocator(), testing.io, .{
        .path = "output.log",
        .dir = tmp.dir,
        .max_bytes = 4096,
        .retention = 1,
        .buffer_bytes = 32,
        .backend = .portable,
        .rotation_interval_ns = 1000,
        .clock = clock.clock(),
    });
    defer output.deinit();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    for (0..100) |index| {
        clock.now = 100 + index;
        try output.writeRecord("one\n");
    }
    try output.flush();
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    try testing.expect(!failing.has_induced_failure);
}

test "timed rolling supports time-only rotation without a size threshold" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var clock: FakeClock = .{ .now = 100 };
    const output = try RollingFileSink.create(testing.allocator, testing.io, .{
        .path = "output.log",
        .dir = tmp.dir,
        .retention = 2,
        .buffer_bytes = 32,
        .backend = .portable,
        .rotation_interval_ns = 10,
        .clock = clock.clock(),
    });
    defer output.deinit();
    for (0..4) |_| try output.writeRecord("record\n");
    clock.now = 109;
    try output.writeRecord("before\n");
    try testing.expectEqual(@as(usize, 0), output.rollover_count);
    clock.now = 110;
    try output.writeRecord("after\n");
    try output.flush();
    try testing.expectEqual(@as(usize, 1), output.rollover_count);
    try expectFile(tmp.dir, "output.log.1", "record\nrecord\nrecord\nrecord\nbefore\n");
    try expectFile(tmp.dir, "output.log", "after\n");
    var forbidden = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.InvalidRollingOptions, RollingFileSink.create(forbidden.allocator(), testing.io, .{ .path = "must-not-create", .retention = 1 }));
    try testing.expect(!forbidden.has_induced_failure);
}
