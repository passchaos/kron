const std = @import("std");
const shared = @import("../shared_admission.zig");
const Atomic = std.atomic.Value;

fn await(event: *std.Io.Event) !void {
    try event.waitTimeout(std.testing.io, .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } });
}

fn awaitEpochChange(epoch: *Atomic(u32), before: u32) !void {
    const deadline = std.Io.Clock.awake.now(std.testing.io).nanoseconds + 5 * std.time.ns_per_s;
    while (epoch.load(.seq_cst) == before) {
        if (std.Io.Clock.awake.now(std.testing.io).nanoseconds > deadline) return error.TestTimeout;
        std.atomic.spinLoopHint();
    }
}

const Pause = struct {
    point: shared.TestingPoint,
    entered: std.Io.Event = .unset,
    permit: std.Io.Event = .unset,
    fired: bool = false,
    visits: usize = 0,

    fn hook(raw: ?*anyopaque, point: shared.TestingPoint) void {
        const self: *Pause = @ptrCast(@alignCast(raw.?));
        if (point != self.point) return;
        self.visits += 1;
        if (self.fired) return;
        self.fired = true;
        self.entered.set(std.testing.io);
        self.permit.waitUncancelable(std.testing.io);
    }
};

const Producer = struct {
    shards: *shared.Shards,
    global: *Atomic(u64),
    epoch: *Atomic(u32),
    shard: usize,
    pause: ?*Pause = null,
    io: std.Io = std.testing.io,
    token: ?*Atomic(u64) = null,
    done: std.Io.Event = .unset,

    fn run(self: *Producer) void {
        shared.testing_hooks = .{
            .forced_shard = self.shard,
            .context = self.pause,
            .pause = if (self.pause != null) Pause.hook else null,
        };
        defer shared.testing_hooks = .{};
        self.token = self.shards.acquire(self.global, self.epoch, self.io);
        self.done.set(std.testing.io);
    }

    fn releaseToken(self: *Producer) void {
        if (self.token) |token| {
            releaseAndWake(token, self.epoch, self.io);
            self.token = null;
        }
    }
};

const Waiter = struct {
    shards: *shared.Shards,
    epoch: *Atomic(u32),
    pause: ?*Pause = null,
    io: std.Io = std.testing.io,
    done: std.Io.Event = .unset,

    fn run(self: *Waiter) void {
        shared.testing_hooks = .{
            .context = self.pause,
            .pause = if (self.pause != null) Pause.hook else null,
        };
        defer shared.testing_hooks = .{};
        self.shards.wait(self.epoch, self.io);
        self.done.set(std.testing.io);
    }
};

fn releaseAndWake(token: *Atomic(u64), epoch: *Atomic(u32), io: std.Io) void {
    const previous = shared.release(token);
    if (previous & shared.count_mask == 1 and previous & (shared.closing_bit | shared.cut_bit) != 0) shared.wake(epoch, io);
}

fn forceShard(index: usize) void {
    shared.testing_hooks = .{ .forced_shard = index };
}

test "shared shards occupy exactly 64 independent cache lines and collisions do not deny admission" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    defer shared.testing_hooks = .{};
    try std.testing.expectEqual(@as(usize, 4096), @sizeOf(shared.Shards));
    for (&shards.lines, 0..) |*line, index| {
        try std.testing.expectEqual(@as(usize, 0), @intFromPtr(&line.word) % 64);
        forceShard(index);
        const token = shards.acquire(&global, &epoch, std.testing.io) orelse return error.UnexpectedRejection;
        try std.testing.expectEqual(&line.word, token);
    }
    forceShard(0);
    const collision = shards.acquire(&global, &epoch, std.testing.io) orelse return error.UnexpectedRejection;
    try std.testing.expectEqual(&shards.lines[0].word, collision);
    try std.testing.expectEqual(@as(u64, 65), shards.activeCount());
    // Changing the hash cannot change the word that a previously issued token
    // releases. All lines keep their own independent modification orders.
    forceShard(63);
    try std.testing.expectEqual(@as(u64, 2), shared.release(collision));
    for (&shards.lines) |*line| try std.testing.expectEqual(@as(u64, 1), shared.release(&line.word));
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    try std.testing.expectEqual(@as(u64, 0), global.load(.seq_cst));
}

test "shared acquire paused after initial global read cannot cross a cut without a fresh revision" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    var pause: Pause = .{ .point = .after_global_read };
    var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 7, .pause = &pause };
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        shards.close(&global);
        shared.wake(&epoch, std.testing.io);
        pause.permit.set(std.testing.io);
        thread.join();
        producer.releaseToken();
    }
    try await(&pause.entered);
    shards.beginCut(&global);
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    shards.wait(&epoch, std.testing.io);
    const cut_revision = global.load(.seq_cst) & shared.revision_mask;
    shards.endCut(&global, &epoch, std.testing.io);
    try std.testing.expect(global.load(.seq_cst) & shared.revision_mask > cut_revision);
    pause.permit.set(std.testing.io);
    try await(&producer.done);
    try std.testing.expect(producer.token != null);
    try std.testing.expectEqual(@as(usize, 2), pause.visits);
    try std.testing.expectEqual(@as(u64, 1), shards.activeCount());
}

test "shared post CAS recheck rolls back cut-crossing count and wakes the cut waiter" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    var producer_pause: Pause = .{ .point = .before_global_recheck };
    var waiter_pause: Pause = .{ .point = .before_wait };
    var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 11, .pause = &producer_pause };
    const producer_thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        shards.close(&global);
        shared.wake(&epoch, std.testing.io);
        producer_pause.permit.set(std.testing.io);
        producer_thread.join();
        producer.releaseToken();
    }
    try await(&producer_pause.entered);
    try std.testing.expectEqual(@as(u64, 1), shards.activeCount());
    shards.beginCut(&global);
    var waiter: Waiter = .{ .shards = &shards, .epoch = &epoch, .pause = &waiter_pause };
    const waiter_thread = try std.Thread.spawn(.{}, Waiter.run, .{&waiter});
    defer {
        producer_pause.permit.set(std.testing.io);
        waiter_pause.permit.set(std.testing.io);
        shared.wake(&epoch, std.testing.io);
        waiter_thread.join();
    }
    try await(&waiter_pause.entered);
    const before = epoch.load(.seq_cst);
    producer_pause.permit.set(std.testing.io);
    // The producer cannot enter capture; it releases the frozen count before
    // waiting on global cut. Letting the waiter enter futex afterward exercises
    // the wake-before-sleep race through the epoch check.
    try awaitEpochChange(&epoch, before);
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    waiter_pause.permit.set(std.testing.io);
    try await(&waiter.done);
    shards.endCut(&global, &epoch, std.testing.io);
    try await(&producer.done);
    try std.testing.expect(producer.token != null);
}

test "shared capture admitted before cut is counted until its exact token releases" {
    inline for (.{ @as(usize, 3), @as(usize, 41) }) |second_shard| {
        var shards: shared.Shards = .{};
        var global: Atomic(u64) = .init(0);
        var epoch: Atomic(u32) = .init(0);
        var held: Pause = .{ .point = .accepted };
        var blocked: Pause = .{ .point = .before_wait };
        var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 3, .pause = &held };
        const producer_thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
        defer {
            held.permit.set(std.testing.io);
            shards.close(&global);
            shared.wake(&epoch, std.testing.io);
            producer_thread.join();
            producer.releaseToken();
        }
        try await(&held.entered);
        forceShard(second_shard);
        defer shared.testing_hooks = .{};
        const other = shards.acquire(&global, &epoch, std.testing.io) orelse return error.UnexpectedRejection;
        var other_held = true;
        defer if (other_held) releaseAndWake(other, &epoch, std.testing.io);
        try std.testing.expectEqual(@as(u64, 2), shards.activeCount());
        shards.beginCut(&global);
        var waiter: Waiter = .{ .shards = &shards, .epoch = &epoch, .pause = &blocked };
        const waiter_thread = try std.Thread.spawn(.{}, Waiter.run, .{&waiter});
        defer {
            held.permit.set(std.testing.io);
            producer.done.waitUncancelable(std.testing.io);
            producer.releaseToken();
            if (other_held) {
                releaseAndWake(other, &epoch, std.testing.io);
                other_held = false;
            }
            blocked.permit.set(std.testing.io);
            shared.wake(&epoch, std.testing.io);
            waiter_thread.join();
        }
        try await(&blocked.entered);
        releaseAndWake(other, &epoch, std.testing.io);
        other_held = false;
        try std.testing.expectEqual(@as(u64, 1), shards.activeCount());
        held.permit.set(std.testing.io);
        try await(&producer.done);
        try std.testing.expect(producer.token != null);
        producer.releaseToken();
        blocked.permit.set(std.testing.io);
        try await(&waiter.done);
        try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
        shards.endCut(&global, &epoch, std.testing.io);
    }
}

test "shared close freezes every line before publishing global closing and stale readers reject" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    var pause: Pause = .{ .point = .after_global_read };
    var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 63, .pause = &pause };
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        shards.close(&global);
        shared.wake(&epoch, std.testing.io);
        pause.permit.set(std.testing.io);
        thread.join();
        producer.releaseToken();
    }
    try await(&pause.entered);
    shards.close(&global);
    shared.wake(&epoch, std.testing.io);
    try std.testing.expect(global.load(.seq_cst) & shared.closing_bit != 0);
    for (&shards.lines) |*line| try std.testing.expect(line.word.load(.seq_cst) & shared.closing_bit != 0);
    pause.permit.set(std.testing.io);
    try await(&producer.done);
    try std.testing.expect(producer.token == null);
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
}

test "shared close after count CAS makes rollback wake admission epoch" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    var pause: Pause = .{ .point = .before_global_recheck };
    var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 32, .pause = &pause };
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        shards.close(&global);
        shared.wake(&epoch, std.testing.io);
        pause.permit.set(std.testing.io);
        thread.join();
        producer.releaseToken();
    }
    try await(&pause.entered);
    shards.close(&global);
    const version = epoch.load(.seq_cst);
    pause.permit.set(std.testing.io);
    try await(&producer.done);
    try std.testing.expect(producer.token == null);
    try std.testing.expectEqual(version + 1, epoch.load(.seq_cst));
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    shards.wait(&epoch, std.testing.io);
}

const Control = struct {
    shards: *shared.Shards,
    global: *Atomic(u64),
    epoch: *Atomic(u32),
    pause: *Pause,
    closing: bool,
    done: std.Io.Event = .unset,

    fn run(self: *Control) void {
        shared.testing_hooks = .{ .context = self.pause, .pause = Pause.hook };
        defer shared.testing_hooks = .{};
        if (self.closing) {
            self.shards.close(self.global);
            shared.wake(self.epoch, std.testing.io);
        } else self.shards.endCut(self.global, self.epoch, std.testing.io);
        self.done.set(std.testing.io);
    }
};

test "shared endCut racing close preserves closing regardless of global publication order" {
    inline for (.{ false, true }) |pause_close| {
        var shards: shared.Shards = .{};
        var global: Atomic(u64) = .init(0);
        var epoch: Atomic(u32) = .init(0);
        shards.beginCut(&global);
        var pause: Pause = .{ .point = if (pause_close) .before_close_publish else .before_end_cut_publish };
        var control: Control = .{ .shards = &shards, .global = &global, .epoch = &epoch, .pause = &pause, .closing = pause_close };
        const thread = try std.Thread.spawn(.{}, Control.run, .{&control});
        defer {
            pause.permit.set(std.testing.io);
            thread.join();
        }
        try await(&pause.entered);
        if (pause_close) shards.endCut(&global, &epoch, std.testing.io) else shards.close(&global);
        pause.permit.set(std.testing.io);
        try await(&control.done);
        try std.testing.expect(global.load(.seq_cst) & shared.closing_bit != 0);
        try std.testing.expectEqual(@as(u64, 0), global.load(.seq_cst) & shared.cut_bit);
        for (&shards.lines) |*line| {
            try std.testing.expectEqual(shared.closing_bit, line.word.load(.seq_cst));
        }
        try std.testing.expect(shards.acquire(&global, &epoch, std.testing.io) == null);
    }
}

test "shared cut rollback reaches stable zero before delayed global closing publication" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    var producer_pause: Pause = .{ .point = .before_global_recheck };
    var close_pause: Pause = .{ .point = .before_close_publish };
    var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 13, .pause = &producer_pause };
    const producer_thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        shards.close(&global);
        shared.wake(&epoch, std.testing.io);
        producer_pause.permit.set(std.testing.io);
        producer_thread.join();
        producer.releaseToken();
    }
    try await(&producer_pause.entered);
    shards.beginCut(&global);
    var closing: Control = .{ .shards = &shards, .global = &global, .epoch = &epoch, .pause = &close_pause, .closing = true };
    const closing_thread = try std.Thread.spawn(.{}, Control.run, .{&closing});
    defer {
        close_pause.permit.set(std.testing.io);
        closing_thread.join();
    }
    try await(&close_pause.entered);
    try std.testing.expectEqual(@as(u64, 0), global.load(.seq_cst) & shared.closing_bit);
    for (&shards.lines) |*line| try std.testing.expect(line.word.load(.seq_cst) & shared.closing_bit != 0);
    const before = epoch.load(.seq_cst);
    producer_pause.permit.set(std.testing.io);
    try await(&producer.done);
    try std.testing.expect(producer.token == null);
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    try std.testing.expectEqual(before + 1, epoch.load(.seq_cst));
    close_pause.permit.set(std.testing.io);
    try await(&closing.done);
    try std.testing.expect(global.load(.seq_cst) & shared.closing_bit != 0);
    // An SC scanner following closing publication must observe the earlier
    // rollback's zero and cannot sleep waiting for an already finished producer.
    try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    shards.wait(&epoch, std.testing.io);
}

test "shared closing rollback wakes each last frozen shard with colliding and independent producers" {
    inline for (.{ @as(usize, 17), @as(usize, 51) }) |second_shard| {
        var shards: shared.Shards = .{};
        var global: Atomic(u64) = .init(0);
        var epoch: Atomic(u32) = .init(0);
        var first_pause: Pause = .{ .point = .before_global_recheck };
        var second_pause: Pause = .{ .point = .before_global_recheck };
        var first: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 17, .pause = &first_pause };
        var second: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = second_shard, .pause = &second_pause };
        const first_thread = try std.Thread.spawn(.{}, Producer.run, .{&first});
        defer {
            shards.close(&global);
            shared.wake(&epoch, std.testing.io);
            first_pause.permit.set(std.testing.io);
            first_thread.join();
            first.releaseToken();
        }
        const second_thread = try std.Thread.spawn(.{}, Producer.run, .{&second});
        defer {
            shards.close(&global);
            shared.wake(&epoch, std.testing.io);
            second_pause.permit.set(std.testing.io);
            second_thread.join();
            second.releaseToken();
        }
        try await(&first_pause.entered);
        try await(&second_pause.entered);
        try std.testing.expectEqual(@as(u64, 2), shards.activeCount());
        shards.beginCut(&global);
        shards.close(&global);
        const before = epoch.load(.seq_cst);
        first_pause.permit.set(std.testing.io);
        try await(&first.done);
        try std.testing.expect(first.token == null);
        try std.testing.expectEqual(@as(u64, 1), shards.activeCount());
        const first_wakes: u32 = if (second_shard == 17) 0 else 1;
        try std.testing.expectEqual(before + first_wakes, epoch.load(.seq_cst));
        second_pause.permit.set(std.testing.io);
        try await(&second.done);
        try std.testing.expect(second.token == null);
        try std.testing.expectEqual(before + first_wakes + 1, epoch.load(.seq_cst));
        try std.testing.expectEqual(@as(u64, 0), shards.activeCount());
    }
}

test "shared revision recheck rejects old observation even when cut has already ended" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(0);
    var epoch: Atomic(u32) = .init(0);
    var pause: Pause = .{ .point = .before_global_recheck };
    var producer: Producer = .{ .shards = &shards, .global = &global, .epoch = &epoch, .shard = 29, .pause = &pause };
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    defer {
        shards.close(&global);
        shared.wake(&epoch, std.testing.io);
        pause.permit.set(std.testing.io);
        thread.join();
        producer.releaseToken();
    }
    try await(&pause.entered);
    shards.beginCut(&global);
    // Exercise revision protection directly. The Runtime normally waits for
    // this count before ending cut; no flags alone can distinguish these reads.
    shards.endCut(&global, &epoch, std.testing.io);
    try std.testing.expectEqual(@as(u64, 2), global.load(.seq_cst));
    pause.permit.set(std.testing.io);
    try await(&producer.done);
    try std.testing.expect(producer.token != null);
    try std.testing.expectEqual(@as(usize, 2), pause.visits);
    try std.testing.expectEqual(@as(u64, 1), shards.activeCount());
}

test "shared revision exhaustion permanently closes instead of rolling over" {
    var shards: shared.Shards = .{};
    var global: Atomic(u64) = .init(shared.revision_mask - 2);
    var epoch: Atomic(u32) = .init(0);
    shards.beginCut(&global);
    shards.endCut(&global, &epoch, std.testing.io);
    try std.testing.expectEqual(shared.revision_mask, global.load(.seq_cst));
    const token = shards.acquire(&global, &epoch, std.testing.io) orelse return error.UnexpectedRejection;
    shards.beginCut(&global);
    try std.testing.expectEqual(shared.revision_mask, global.load(.seq_cst) & shared.revision_mask);
    try std.testing.expect(global.load(.seq_cst) & shared.closing_bit != 0);
    for (&shards.lines) |*line| try std.testing.expect(line.word.load(.seq_cst) & shared.closing_bit != 0);
    releaseAndWake(token, &epoch, std.testing.io);
    shards.wait(&epoch, std.testing.io);
    shards.endCut(&global, &epoch, std.testing.io);
    try std.testing.expectEqual(shared.closing_bit | shared.revision_mask, global.load(.seq_cst));
    try std.testing.expect(shards.acquire(&global, &epoch, std.testing.io) == null);
}

test "shared cold count scan saturates rather than overflowing to a false zero" {
    var shards: shared.Shards = .{};
    for (&shards.lines) |*line| line.word.store(shared.count_mask, .seq_cst);
    try std.testing.expectEqual(std.math.maxInt(u64), shards.activeCount());
}
