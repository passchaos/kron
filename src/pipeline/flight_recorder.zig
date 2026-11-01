const std = @import("std");
const Sink = @import("../sink/interface.zig").Sink;

pub const Options = struct {
    capacity: usize,
    max_record_bytes: usize,
};

pub const Stats = struct {
    /// Cumulative successful captures, including records later overwritten.
    records: u64 = 0,
    bytes: u64 = 0,
    /// Captures that replaced an older, still buffered record.
    overruns: u64 = 0,
    buffered_records: usize = 0,
    buffered_bytes: usize = 0,
    allocated_bytes: usize = 0,
};

pub const InitError = error{ InvalidCapacity, InvalidRecordSize, RecordBudgetOverflow };

/// Optional memory diagnostics, with complete opaque records and newest-N
/// retention. This provides no crash recovery or durable acknowledgement.
/// Initialization allocates and touches two capacity-sized byte buffers and
/// two length arrays: the ring plus a bounded dump snapshot. Capture and dump
/// never allocate from the recorder's allocator after create.
///
/// Capture, stats, and snapshot/clear use an internal Io.Mutex. Target callbacks
/// run outside this mutex; a dump may safely capture another record. Concurrent
/// or reentrant dumps return DumpInProgress. A successful clear removes only
/// the snapshot records still retained, preserving captures made during dump.
/// A failed write or flush does not clear; retry may duplicate a delivered
/// prefix. Ordinary newest-N overwrites can still occur during a failed dump.
/// The owner must finish concurrent calls before deinit.
pub const FlightRecorder = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    mutex: std.Io.Mutex = .init,
    dump_in_progress: std.atomic.Value(bool) = .init(false),
    storage: []u8,
    lengths: []usize,
    snapshot_storage: []u8,
    snapshot_lengths: []usize,
    head: usize = 0,
    clear_pending: usize = 0,
    counters: Stats,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) (std.mem.Allocator.Error || InitError)!*FlightRecorder {
        if (options.capacity == 0) return error.InvalidCapacity;
        if (options.max_record_bytes == 0) return error.InvalidRecordSize;
        const storage_bytes = std.math.mul(usize, options.capacity, options.max_record_bytes) catch
            return error.RecordBudgetOverflow;
        const both_storage_bytes = std.math.mul(usize, storage_bytes, 2) catch
            return error.RecordBudgetOverflow;
        const metadata_bytes = std.math.mul(usize, options.capacity, 2 * @sizeOf(usize)) catch
            return error.RecordBudgetOverflow;
        const arrays_bytes = std.math.add(usize, both_storage_bytes, metadata_bytes) catch
            return error.RecordBudgetOverflow;
        const allocated_bytes = std.math.add(usize, arrays_bytes, @sizeOf(FlightRecorder)) catch
            return error.RecordBudgetOverflow;

        const self = try allocator.create(FlightRecorder);
        errdefer allocator.destroy(self);
        const storage = try allocator.alloc(u8, storage_bytes);
        errdefer allocator.free(storage);
        const lengths = try allocator.alloc(usize, options.capacity);
        errdefer allocator.free(lengths);
        const snapshot_storage = try allocator.alloc(u8, storage_bytes);
        errdefer allocator.free(snapshot_storage);
        const snapshot_lengths = try allocator.alloc(usize, options.capacity);
        errdefer allocator.free(snapshot_lengths);
        // Touch every reserved byte, moving first-touch faults into startup.
        @memset(storage, 0);
        @memset(lengths, 0);
        @memset(snapshot_storage, 0);
        @memset(snapshot_lengths, 0);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .options = options,
            .storage = storage,
            .lengths = lengths,
            .snapshot_storage = snapshot_storage,
            .snapshot_lengths = snapshot_lengths,
            .counters = .{ .allocated_bytes = allocated_bytes },
        };
        return self;
    }

    pub fn deinit(self: *FlightRecorder) void {
        std.debug.assert(!self.dump_in_progress.load(.acquire));
        const allocator = self.allocator;
        allocator.free(self.snapshot_lengths);
        allocator.free(self.snapshot_storage);
        allocator.free(self.lengths);
        allocator.free(self.storage);
        allocator.destroy(self);
    }

    pub fn sink(self: *FlightRecorder) Sink {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn writeRecord(self: *FlightRecorder, record: []const u8) error{RecordTooLarge}!void {
        if (record.len > self.options.max_record_bytes) return error.RecordTooLarge;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (self.counters.buffered_records == self.options.capacity) {
            self.counters.buffered_bytes -= self.lengths[self.head];
            self.head = self.next(self.head);
            self.counters.buffered_records -= 1;
            self.counters.overruns +|= 1;
            // Snapshot members are always the oldest retained records. New
            // captures must never be mistaken for records cleared by dump.
            if (self.clear_pending != 0) self.clear_pending -= 1;
        }
        const slot = self.index(self.counters.buffered_records);
        @memcpy(self.storage[slot * self.options.max_record_bytes ..][0..record.len], record);
        self.lengths[slot] = record.len;
        self.counters.buffered_records += 1;
        self.counters.buffered_bytes += record.len;
        self.counters.records +|= 1;
        self.counters.bytes +|= @intCast(record.len);
    }

    /// Confirms prior captures are present in this memory buffer. It does not
    /// dump to an external target or provide persistent acknowledgement.
    pub fn flush(self: *FlightRecorder) void {
        self.mutex.lockUncancelable(self.io);
        self.mutex.unlock(self.io);
    }

    pub fn sync(_: *FlightRecorder) error{UnsupportedDurability}!void {
        return error.UnsupportedDurability;
    }

    pub fn stats(self: *FlightRecorder) Stats {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.counters;
    }

    pub fn dump(self: *FlightRecorder, target: Sink, clear: bool) !void {
        if (self.dump_in_progress.cmpxchgStrong(false, true, .acq_rel, .acquire) != null)
            return error.DumpInProgress;
        var completed = false;
        defer {
            self.mutex.lockUncancelable(self.io);
            if (completed and clear) {
                while (self.clear_pending != 0) {
                    self.counters.buffered_bytes -= self.lengths[self.head];
                    self.lengths[self.head] = 0;
                    self.head = self.next(self.head);
                    self.counters.buffered_records -= 1;
                    self.clear_pending -= 1;
                }
            }
            self.clear_pending = 0;
            self.mutex.unlock(self.io);
            self.dump_in_progress.store(false, .release);
        }

        self.mutex.lockUncancelable(self.io);
        const count = self.counters.buffered_records;
        self.clear_pending = if (clear) count else 0;
        for (0..count) |i| {
            const slot = self.index(i);
            const length = self.lengths[slot];
            self.snapshot_lengths[i] = length;
            @memcpy(self.snapshot_storage[i * self.options.max_record_bytes ..][0..length], self.storage[slot * self.options.max_record_bytes ..][0..length]);
        }
        self.mutex.unlock(self.io);

        for (self.snapshot_lengths[0..count], 0..) |length, i| {
            try target.writeRecord(self.snapshot_storage[i * self.options.max_record_bytes ..][0..length]);
        }
        try target.flush();
        completed = true;
    }

    fn index(self: *const FlightRecorder, offset: usize) usize {
        // Avoid head + offset overflow even for very large validated budgets.
        const before_wrap = self.options.capacity - self.head;
        return if (offset < before_wrap) self.head + offset else offset - before_wrap;
    }

    fn next(self: *const FlightRecorder, slot: usize) usize {
        return if (slot == self.options.capacity - 1) 0 else slot + 1;
    }

    fn writeErased(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*FlightRecorder, @ptrCast(@alignCast(context)))).writeRecord(record);
    }

    fn flushErased(context: *anyopaque) anyerror!void {
        (@as(*FlightRecorder, @ptrCast(@alignCast(context)))).flush();
    }

    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*FlightRecorder, @ptrCast(@alignCast(context)))).sync();
    }

    const vtable: Sink.VTable = .{ .writeRecord = writeErased, .flush = flushErased, .sync = syncErased };
};

test "flight recorder retains FIFO order across wraps and clear" {
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    const recorder = try FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 3, .max_record_bytes = 8 });
    defer recorder.deinit();
    for ([_][]const u8{ "one", "two", "three", "four" }) |record| try recorder.sink().writeRecord(record);
    var bytes: [64]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    try recorder.dump(output.sink(), false);
    try std.testing.expectEqualStrings("twothreefour", output.written());
    try std.testing.expectEqual(@as(usize, 3), output.records);
    try std.testing.expectEqual(@as(usize, 1), output.flush_count);
    const before = recorder.stats();
    try std.testing.expectEqual(@as(u64, 4), before.records);
    try std.testing.expectEqual(@as(u64, 15), before.bytes);
    try std.testing.expectEqual(@as(u64, 1), before.overruns);
    try std.testing.expectEqual(@as(usize, 3), before.buffered_records);
    try std.testing.expectEqual(@as(usize, 12), before.buffered_bytes);
    try recorder.writeRecord("five");
    try recorder.writeRecord("six");
    output.clear();
    try recorder.dump(output.sink(), true);
    try std.testing.expectEqualStrings("fourfivesix", output.written());
    try std.testing.expectEqual(@as(usize, 0), recorder.stats().buffered_records);
    try std.testing.expectEqual(@as(usize, 0), recorder.stats().buffered_bytes);
    try std.testing.expectEqual(@as(u64, 3), recorder.stats().overruns);
    try recorder.writeRecord("again");
    output.clear();
    try recorder.dump(output.sink(), false);
    try std.testing.expectEqualStrings("again", output.written());
    try std.testing.expectError(error.UnsupportedDurability, recorder.sink().sync());
}

test "flight recorder copies full opaque bytes and rejects oversized records atomically" {
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    const recorder = try FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 2, .max_record_bytes = 512 });
    defer recorder.deinit();
    var original: [512]u8 = undefined;
    for (&original, 0..) |*byte, i| byte.* = @truncate(i);
    const expected = original;
    try recorder.writeRecord(&original);
    @memset(&original, 0);
    try recorder.writeRecord(&.{ 0, 255, 0, 10 });
    const before = recorder.stats();
    const oversized = [_]u8{1} ** 513;
    try std.testing.expectError(error.RecordTooLarge, recorder.sink().writeRecord(&oversized));
    try std.testing.expectEqualDeep(before, recorder.stats());
    var bytes: [600]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    try recorder.dump(output.sink(), false);
    try std.testing.expectEqualSlices(u8, &expected, output.written()[0..512]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 10 }, output.written()[512..]);
    try std.testing.expectEqual(@as(usize, 2), output.records);
}

test "flight recorder failed writes and flushes keep records for retry" {
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    const recorder = try FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 3, .max_record_bytes = 8 });
    defer recorder.deinit();
    for ([_][]const u8{ "a", "bb", "ccc" }) |record| try recorder.writeRecord(record);
    const before = recorder.stats();
    var bytes: [64]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    output.fail_after_records = 1;
    try std.testing.expectError(error.InjectedWriteFailure, recorder.dump(output.sink(), true));
    try std.testing.expectEqualStrings("a", output.written());
    try std.testing.expectEqualDeep(before, recorder.stats());
    output.clear();
    output.fail_after_records = null;
    output.fail_flush = true;
    try std.testing.expectError(error.InjectedFlushFailure, recorder.dump(output.sink(), true));
    try std.testing.expectEqualStrings("abbccc", output.written());
    try std.testing.expectEqualDeep(before, recorder.stats());
    output.clear();
    output.fail_flush = false;
    try recorder.dump(output.sink(), true);
    try std.testing.expectEqualStrings("abbccc", output.written());
    try std.testing.expectEqual(@as(usize, 0), recorder.stats().buffered_records);
}

test "flight recorder capture and dump allocate nothing after startup" {
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const recorder = try FlightRecorder.create(allocator.allocator(), std.testing.io, .{ .capacity = 4, .max_record_bytes = 16 });
    defer recorder.deinit();
    const allocations = allocator.allocations;
    allocator.fail_index = allocator.alloc_index;
    for (0..1000) |_| try recorder.sink().writeRecord("record");
    try recorder.sink().flush();
    var bytes: [64]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    try recorder.dump(output.sink(), true);
    try std.testing.expectEqualStrings("recordrecordrecordrecord", output.written());
    try std.testing.expectEqual(allocations, allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 996), recorder.stats().overruns);
}

test "flight recorder dump callbacks may capture and cannot reenter dump" {
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    const Target = struct {
        recorder: *FlightRecorder,
        output: *MemorySink,
        entered: bool = false,
        rejected_reentry: bool = false,

        fn write(context: *anyopaque, record: []const u8) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (!self.entered) {
                self.entered = true;
                try self.recorder.writeRecord("late");
                _ = self.recorder.stats();
                self.recorder.dump(self.output.sink(), false) catch |err| {
                    if (err != error.DumpInProgress) return err;
                    self.rejected_reentry = true;
                };
            }
            try self.output.writeRecord(record);
        }
        fn flush_(context: *anyopaque) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try self.output.flush();
        }
        fn sync_(_: *anyopaque) anyerror!void {
            return error.UnsupportedDurability;
        }
        const vtable_: Sink.VTable = .{ .writeRecord = write, .flush = flush_, .sync = sync_ };
    };
    const recorder = try FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 2, .max_record_bytes = 8 });
    defer recorder.deinit();
    try recorder.writeRecord("old1");
    try recorder.writeRecord("old2");
    var bytes: [64]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    var target: Target = .{ .recorder = recorder, .output = &output };
    try recorder.dump(.{ .context = &target, .vtable = &Target.vtable_ }, true);
    try std.testing.expect(target.rejected_reentry);
    try std.testing.expectEqualStrings("old1old2", output.written());
    try std.testing.expectEqual(@as(usize, 1), recorder.stats().buffered_records);
    try std.testing.expectEqual(@as(u64, 1), recorder.stats().overruns);
    output.clear();
    try recorder.dump(output.sink(), false);
    try std.testing.expectEqualStrings("late", output.written());
}

test "flight recorder initialization validates and cleans all allocation failures" {
    const Check = struct {
        fn init(allocator: std.mem.Allocator) !void {
            const recorder = try FlightRecorder.create(allocator, std.testing.io, .{ .capacity = 2, .max_record_bytes = 16 });
            defer recorder.deinit();
            for (recorder.storage) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
            for (recorder.snapshot_storage) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
            try std.testing.expectEqual(@as(usize, 2 * 2 * 16 + 2 * 2 * @sizeOf(usize) + @sizeOf(FlightRecorder)), recorder.stats().allocated_bytes);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.init, .{});
    try std.testing.expectError(error.InvalidCapacity, FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 0, .max_record_bytes = 16 }));
    try std.testing.expectError(error.InvalidRecordSize, FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 2, .max_record_bytes = 0 }));
    try std.testing.expectError(error.RecordBudgetOverflow, FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = std.math.maxInt(usize), .max_record_bytes = 2 }));
}

test "flight recorder captured codec frame contains no original secret" {
    const codec = @import("../core/codec.zig");
    const fields = @import("../core/field.zig");
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    const recorder = try FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 2, .max_record_bytes = 512 });
    defer recorder.deinit();
    var frame_buffer: [512]u8 = undefined;
    const frame = try codec.encode(.{
        .level = .trace,
        .scope = "debug.flight",
        .message = "request captured",
        .timestamp_ns = 0,
        .fields = &.{fields.kv("password", fields.secret("flight-raw-secret"))},
    }, &frame_buffer);
    try recorder.sink().writeRecord(frame);
    const frame_length = frame.len;
    @memset(&frame_buffer, 0);
    var bytes: [512]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    try recorder.dump(output.sink(), false);
    try std.testing.expectEqual(frame_length, output.written().len);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "flight-raw-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, recorder.storage, "flight-raw-secret") == null);
    var scratch: [1]fields.Field = undefined;
    const decoded = try codec.decode(output.written(), &scratch);
    try std.testing.expectEqualStrings(fields.redacted, decoded.fields[0].value.string);
}

test "flight recorder supports concurrent capture and dump with whole records" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const MemorySink = @import("../sink/memory.zig").MemorySink;
    const Context = struct {
        recorder: *FlightRecorder,
        id: u64,

        fn capture(context: *@This()) void {
            for (0..500) |i| {
                var record: [16]u8 = undefined;
                std.mem.writeInt(u64, record[0..8], context.id, .little);
                std.mem.writeInt(u64, record[8..16], i, .little);
                context.recorder.writeRecord(&record) catch unreachable;
            }
        }
        fn check(output: *MemorySink) !void {
            try std.testing.expectEqual(output.records * 16, output.written().len);
            var offset: usize = 0;
            while (offset < output.written().len) : (offset += 16) {
                try std.testing.expect(std.mem.readInt(u64, output.written()[offset..][0..8], .little) < 4);
                try std.testing.expect(std.mem.readInt(u64, output.written()[offset + 8 ..][0..8], .little) < 500);
            }
        }
    };
    const recorder = try FlightRecorder.create(std.testing.allocator, std.testing.io, .{ .capacity = 32, .max_record_bytes = 16 });
    defer recorder.deinit();
    var contexts: [4]Context = undefined;
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    defer for (threads[0..started]) |thread| thread.join();
    for (&threads, &contexts, 0..) |*thread, *context, i| {
        context.* = .{ .recorder = recorder, .id = i };
        thread.* = try std.Thread.spawn(.{}, Context.capture, .{context});
        started += 1;
    }
    var bytes: [32 * 16]u8 = undefined;
    var output = MemorySink.initBuffer(&bytes);
    for (0..30) |_| {
        output.clear();
        try recorder.dump(output.sink(), true);
        try Context.check(&output);
    }
    for (threads[0..started]) |thread| thread.join();
    started = 0;
    output.clear();
    try recorder.dump(output.sink(), true);
    try Context.check(&output);
    try std.testing.expectEqual(@as(u64, 2000), recorder.stats().records);
    try std.testing.expectEqual(@as(u64, 32000), recorder.stats().bytes);
    try std.testing.expectEqual(@as(usize, 0), recorder.stats().buffered_records);
}
