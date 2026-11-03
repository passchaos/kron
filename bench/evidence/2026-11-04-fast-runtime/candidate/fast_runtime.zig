//! Single-producer volatile JSON fast path. The producer renders the final
//! record into a bounded SPSC text ring; one consumer writes and flushes the
//! sink. No journal, CRC, recovery, filters, sampling or redaction. The
//! durable Runtime remains the default owner.

const std = @import("std");
const builtin = @import("builtin");
const Sink = @import("../sink/interface.zig").Sink;
const Level = @import("level.zig").Level;
const Clock = @import("../platform/clock.zig").Clock;
const Event = @import("event.zig").Event;
const common = @import("../encoder/common.zig");
const LoggerModule = @import("logger.zig");
const types = @import("runtime_types.zig");
const MemorySink = @import("../sink/memory.zig").MemorySink;

const Atomic = std.atomic.Value;

pub const Health = struct {
    accepted: u64,
    written: u64,
    dropped_full: u64,
    dropped_oversize: u64,
    pending: usize,
    errors: u64,
    state: State,
};

pub const State = enum(u8) { running, closing, closed };

pub const Options = struct {
    sink: Sink,
    timestamp: ?*@import("../time/root.zig").Formatter = null,
    capacity: usize = 256,
    max_record_bytes: usize = 1024,
    overflow: types.Overflow = .block,
    min_level: Level = .info,
    idle: types.Idle = .sleep,
    clock: Clock = .{},
    session: u64 = std.math.maxInt(u64),
};

const Slot = struct {
    state: Atomic(u64) = .init(0),
    length: usize = 0,
};

const TextRing = struct {
    allocator: std.mem.Allocator,
    capacity: usize,
    record_bytes: usize,
    slots: []Slot,
    storage: []u8,
    tail: Atomic(u64) = .init(0),
    head: Atomic(u64) = .init(0),

    fn create(allocator: std.mem.Allocator, capacity: usize, record_bytes: usize) !TextRing {
        if (capacity == 0 or record_bytes == 0) return error.InvalidOptions;
        const slots = try allocator.alloc(Slot, capacity);
        errdefer allocator.free(slots);
        @memset(slots, .{});
        const storage = try allocator.alloc(u8, capacity * record_bytes);
        errdefer allocator.free(storage);
        return .{ .allocator = allocator, .capacity = capacity, .record_bytes = record_bytes, .slots = slots, .storage = storage };
    }

    fn destroy(self: *TextRing) void {
        const allocator = self.allocator;
        allocator.free(self.storage);
        allocator.free(self.slots);
    }

    fn index(self: *const TextRing, position: u64) usize {
        return @intCast(position % self.capacity);
    }

    fn tag(position: u64, ready: bool) u64 {
        return ((position + 1) << 1) | @intFromBool(ready);
    }

    fn claim(self: *TextRing) ?Claim {
        const position = self.tail.load(.monotonic);
        const head = self.head.load(.acquire);
        if (position - head >= self.capacity) return null;
        const slot = &self.slots[self.index(position)];
        if (slot.state.load(.acquire) != 0) return null;
        return .{ .ring = self, .position = position, .buffer = self.storage[self.index(position) * self.record_bytes ..][0..self.record_bytes] };
    }

    fn peek(self: *TextRing) ?[]const u8 {
        var head = self.head.load(.monotonic);
        while (true) {
            const tail = self.tail.load(.acquire);
            if (head == tail) return null;
            const slot = &self.slots[self.index(head)];
            const state = slot.state.load(.acquire);
            if (state == tag(head, false)) {
                slot.state.store(0, .release);
                head += 1;
                self.head.store(head, .release);
                continue;
            }
            if (state != tag(head, true)) return null;
            if (slot.length > self.record_bytes) return null;
            return self.storage[self.index(head) * self.record_bytes ..][0..slot.length];
        }
    }

    fn release(self: *TextRing) void {
        const head = self.head.load(.monotonic);
        const slot = &self.slots[self.index(head)];
        slot.state.store(0, .release);
        self.head.store(head + 1, .release);
    }

    fn empty(self: *TextRing) bool {
        return self.head.load(.acquire) == self.tail.load(.acquire);
    }

    fn pending(self: *TextRing) usize {
        return @intCast(self.tail.load(.acquire) - self.head.load(.acquire));
    }
};

const Claim = struct {
    ring: *TextRing,
    position: u64,
    buffer: []u8,

    fn publish(self: Claim, length: usize) void {
        std.debug.assert(length <= self.buffer.len);
        const slot = &self.ring.slots[self.ring.index(self.position)];
        slot.length = length;
        slot.state.store(TextRing.tag(self.position, true), .release);
        self.ring.tail.store(self.position + 1, .release);
    }

    fn abort(self: Claim) void {
        const slot = &self.ring.slots[self.ring.index(self.position)];
        slot.state.store(TextRing.tag(self.position, false), .release);
        self.ring.tail.store(self.position + 1, .release);
    }
};

pub const FastRuntime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    ring: TextRing,
    sink: Sink,
    timestamp: ?*@import("../time/root.zig").Formatter,
    clock: Clock,
    min_level: Level,
    overflow: types.Overflow,
    idle: types.Idle,
    session: u64,
    sequence: Atomic(u64) = .init(0),
    state: Atomic(State) = .init(.running),
    wake_epoch: Atomic(u32) = .init(0),
    flush_epoch: Atomic(u32) = .init(0),
    flush_requested: Atomic(bool) = .init(false),
    worker_sleeping: Atomic(bool) = .init(false),
    producer_waiting: Atomic(bool) = .init(false),
    worker: ?std.Thread = null,
    accepted: Atomic(u64) = .init(0),
    written: Atomic(u64) = .init(0),
    dropped_full: Atomic(u64) = .init(0),
    dropped_oversize: Atomic(u64) = .init(0),
    errors: Atomic(u64) = .init(0),
    last_error: Atomic(u16) = .init(0),

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*FastRuntime {
        if (builtin.single_threaded) return error.ThreadsUnavailable;
        if (options.capacity == 0 or options.max_record_bytes == 0) return error.InvalidOptions;
        if (options.overflow == .fallback_sync) return error.InvalidOptions;
        const self = try allocator.create(FastRuntime);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .ring = try TextRing.create(allocator, options.capacity, options.max_record_bytes),
            .sink = options.sink,
            .timestamp = options.timestamp,
            .clock = options.clock,
            .min_level = options.min_level,
            .overflow = options.overflow,
            .idle = options.idle,
            .session = options.session,
        };
        errdefer self.ring.destroy();
        self.worker = try std.Thread.spawn(.{}, workerMain, .{self});
        return self;
    }

    pub fn destroy(self: *FastRuntime) void {
        self.shutdown() catch {};
        const allocator = self.allocator;
        self.ring.destroy();
        allocator.destroy(self);
    }

    pub fn logger(self: *FastRuntime, scope: []const u8) LoggerModule.Logger(FastRuntime, .trace) {
        return .init(self, scope);
    }

    pub fn health(self: *FastRuntime) Health {
        return .{
            .accepted = self.accepted.load(.monotonic),
            .written = self.written.load(.monotonic),
            .dropped_full = self.dropped_full.load(.monotonic),
            .dropped_oversize = self.dropped_oversize.load(.monotonic),
            .pending = self.ring.pending(),
            .errors = self.errors.load(.monotonic),
            .state = self.state.load(.acquire),
        };
    }

    pub fn flush(self: *FastRuntime, boundary: types.Flush) !void {
        if (boundary == .durable) return error.UnsupportedDurability;
        const observed = self.flush_epoch.load(.seq_cst);
        self.flush_requested.store(true, .release);
        self.wake();
        while (self.flush_epoch.load(.seq_cst) == observed) {
            if (self.state.load(.acquire) == .closed and self.ring.empty()) return;
            self.io.futexWaitUncancelable(u32, &self.flush_epoch.raw, observed);
        }
        if (self.last_error.load(.acquire) != 0) return error.DeliveryFailed;
    }

    pub fn shutdown(self: *FastRuntime) !void {
        if (self.worker) |thread| {
            self.state.store(.closing, .release);
            self.wake();
            thread.join();
            self.worker = null;
        }
        self.state.store(.closed, .release);
        if (self.last_error.load(.acquire) != 0) return error.DeliveryFailed;
    }

    // Logger owner interface.
    pub fn enabled(self: *FastRuntime, level: Level, _: []const u8) bool {
        return self.state.load(.acquire) == .running and self.min_level.allows(level);
    }

    pub fn begin(self: *FastRuntime, level: Level, _: []const u8) LoggerModule.BeginResult {
        if (self.state.load(.acquire) != .running) return .closed;
        if (!self.min_level.allows(level)) return .filtered;
        return .{ .ready = .{ .route_mask = 1, .config_generation = 1 } };
    }

    pub fn end(self: *FastRuntime) void {
        _ = self;
    }

    pub fn endAdmission(self: *FastRuntime, _: LoggerModule.Admission) void {
        _ = self;
    }

    pub fn nowNs(self: *FastRuntime) i64 {
        return self.clock.realNow(self.io);
    }

    pub fn captureFailed(self: *FastRuntime, err: anyerror) void {
        self.recordError(err);
    }

    pub fn submit(self: *FastRuntime, _: LoggerModule.Admission, event: Event) !LoggerModule.EmitResult {
        if (self.state.load(.acquire) != .running) return .rejected_closing;
        while (true) {
            const claim = self.ring.claim() orelse {
                if (self.state.load(.acquire) != .running) return .rejected_closing;
                if (self.overflow == .drop_newest) {
                    _ = self.dropped_full.fetchAdd(1, .monotonic);
                    return .dropped_full;
                }
                const observed = self.wake_epoch.load(.seq_cst);
                self.producer_waiting.store(true, .seq_cst);
                self.io.futexWaitUncancelable(u32, &self.wake_epoch.raw, observed);
                self.producer_waiting.store(false, .seq_cst);
                continue;
            };
            var submitted = event;
            submitted.session = self.session;
            submitted.sequence = self.sequence.fetchAdd(1, .monotonic) + 1;
            var writer = std.Io.Writer.fixed(claim.buffer);
            common.encodeDecoded(.json, submitted, self.timestamp, &writer) catch |err| {
                claim.abort();
                self.wake();
                if (err == error.WriteFailed) {
                    _ = self.dropped_oversize.fetchAdd(1, .monotonic);
                    return .dropped_oversize;
                }
                self.recordError(err);
                return err;
            };
            claim.publish(writer.buffered().len);
            _ = self.accepted.fetchAdd(1, .monotonic);
            self.wake();
            return .accepted;
        }
    }

    fn recordError(self: *FastRuntime, err: anyerror) void {
        _ = self.errors.fetchAdd(1, .monotonic);
        self.last_error.store(@intFromError(err), .release);
    }

    fn wake(self: *FastRuntime) void {
        _ = self.wake_epoch.fetchAdd(1, .seq_cst);
        if (self.worker_sleeping.load(.seq_cst) or self.producer_waiting.load(.seq_cst)) self.io.futexWake(u32, &self.wake_epoch.raw, std.math.maxInt(u32));
    }

    fn workerMain(self: *FastRuntime) void {
        while (true) {
            var wrote = false;
            while (self.ring.peek()) |bytes| {
                self.sink.writeRecord(bytes) catch |err| self.recordError(err);
                self.ring.release();
                _ = self.written.fetchAdd(1, .monotonic);
                wrote = true;
                self.wake();
            }
            if (self.flush_requested.swap(false, .acq_rel)) {
                self.sink.flush() catch |err| self.recordError(err);
                _ = self.flush_epoch.fetchAdd(1, .release);
                self.io.futexWake(u32, &self.flush_epoch.raw, std.math.maxInt(u32));
            }
            if (self.state.load(.acquire) == .closing and self.ring.empty()) {
                self.sink.flush() catch |err| self.recordError(err);
                _ = self.flush_epoch.fetchAdd(1, .release);
                self.io.futexWake(u32, &self.flush_epoch.raw, std.math.maxInt(u32));
                self.state.store(.closed, .release);
                return;
            }
            if (!wrote and !self.flush_requested.load(.acquire)) {
                if (self.idle == .spin) {
                    std.atomic.spinLoopHint();
                    continue;
                }
                self.worker_sleeping.store(true, .seq_cst);
                const observed = self.wake_epoch.load(.seq_cst);
                if (self.wake_epoch.load(.seq_cst) == observed) self.io.futexWaitUncancelable(u32, &self.wake_epoch.raw, observed);
                self.worker_sleeping.store(false, .seq_cst);
            }
        }
    }
};

test "fast runtime renders, drains and flushes" {
    var bytes: [8192]u8 = undefined;
    var sink = MemorySink.initBuffer(&bytes);
    const fast = try FastRuntime.create(std.testing.allocator, std.testing.io, .{
        .sink = sink.sink(),
        .capacity = 8,
        .max_record_bytes = 1024,
        .clock = Clock.zeroTimestamp(),
        .session = 42,
    });
    defer fast.destroy();
    const log = fast.logger("fast");
    for (0..3) |index| _ = try log.tryEmit(.info, "event", .{ .field0 = @as(u64, index) });
    try fast.flush(.written);
    const health = fast.health();
    try std.testing.expectEqual(@as(u64, 3), health.accepted);
    try std.testing.expectEqual(@as(u64, 3), health.written);
    try std.testing.expectEqual(@as(usize, 0), health.pending);
    try std.testing.expectEqual(@as(usize, 3), sink.records);
    try std.testing.expect(std.mem.indexOf(u8, sink.written(), "field0") != null);
}
