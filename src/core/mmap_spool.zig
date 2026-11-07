//! Candidate single-producer volatile output path: the producer renders the
//! final JSON directly into a file-backed shared mapping, while one writer
//! thread publishes dirty ranges with msync so writeback overlaps rendering.
//! There is no journal, CRC, recovery or ring handoff; the durable Runtime
//! remains the default owner. This module is an isolated measurement candidate
//! and is not part of the production API.

const std = @import("std");
const builtin = @import("builtin");
const Level = @import("level.zig").Level;
const Clock = @import("../platform/clock.zig").Clock;
const Event = @import("event.zig").Event;
const common = @import("../encoder/common.zig");
const LoggerModule = @import("logger.zig");
const types = @import("runtime_types.zig");
const Mapping = @import("../platform/mapping.zig").Mapping;

const Atomic = std.atomic.Value;
const sync_threshold = 1024 * 1024;

pub const State = enum(u8) { running, closing, closed };

pub const Health = struct {
    accepted: u64,
    written: u64,
    dropped_full: u64,
    dropped_oversize: u64,
    pending: usize,
    errors: u64,
    state: State,
};

pub const Options = struct {
    path: []const u8,
    capacity_bytes: usize = 64 * 1024 * 1024,
    timestamp: ?*@import("../time/root.zig").Formatter = null,
    min_level: Level = .info,
    clock: Clock = .{},
    session: u64 = std.math.maxInt(u64),
    idle: types.Idle = .sleep,
    /// When false, the producer owns the mapping and `flush` schedules the
    /// dirty range directly; no writer thread competes for the core budget.
    writer_thread: bool = true,
    /// Reuse one captured timestamp for this many calls. One keeps exact
    /// timestamps; larger values trade timestamp freshness for fewer clock
    /// reads in the volatile fast path.
    timestamp_period: usize = 1,
};

pub const MmapSpool = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mapping: Mapping,
    offset: usize = 0,
    timestamp: ?*@import("../time/root.zig").Formatter,
    clock: Clock,
    min_level: Level,
    session: u64,
    idle: types.Idle,
    timestamp_period: usize = 1,
    timestamp_counter: usize = 0,
    cached_now: i64 = 0,
    sequence: u64 = 0,
    accepted: u64 = 0,
    written: u64 = 0,
    dropped_full: u64 = 0,
    dropped_oversize: u64 = 0,
    errors: Atomic(u64) = .init(0),
    last_error: Atomic(u16) = .init(0),
    published: Atomic(usize) = .init(0),
    synced: Atomic(usize) = .init(0),
    state: Atomic(State) = .init(.running),
    flush_requested: Atomic(bool) = .init(false),
    flush_epoch: Atomic(u32) = .init(0),
    wake_epoch: Atomic(u32) = .init(0),
    worker_sleeping: Atomic(bool) = .init(false),
    worker: ?std.Thread = null,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*MmapSpool {
        if (builtin.single_threaded) return error.ThreadsUnavailable;
        if (options.path.len == 0 or options.capacity_bytes == 0) return error.InvalidOptions;
        if (options.capacity_bytes > std.math.maxInt(i64)) return error.InvalidOptions;

        // The mapping helper opens an existing file with an exact size and
        // rejects a mismatched layout. A benchmark artifact is recreated per
        // trial, so remove a stale entry through its parent directory first.
        const parent = std.fs.path.dirname(options.path) orelse ".";
        const dir = try std.Io.Dir.cwd().openDir(io, parent, .{});
        defer dir.close(io);
        dir.deleteFile(io, std.fs.path.basename(options.path)) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        const self = try allocator.create(MmapSpool);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .mapping = try Mapping.open(io, options.path, options.capacity_bytes),
            .timestamp = options.timestamp,
            .clock = options.clock,
            .min_level = options.min_level,
            .session = options.session,
            .idle = options.idle,
            .timestamp_period = options.timestamp_period,
        };
        errdefer self.mapping.deinit();
        self.worker = try std.Thread.spawn(.{}, workerMain, .{self});
        return self;
    }

    pub fn destroy(self: *MmapSpool) void {
        self.shutdown() catch {};
        self.mapping.deinit();
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn logger(self: *MmapSpool, scope: []const u8) LoggerModule.Logger(MmapSpool, .trace) {
        return .init(self, scope);
    }

    pub fn health(self: *MmapSpool) Health {
        return .{
            .accepted = self.accepted,
            .written = self.written,
            .dropped_full = self.dropped_full,
            .dropped_oversize = self.dropped_oversize,
            .pending = self.published.load(.acquire) - self.synced.load(.acquire),
            .errors = self.errors.load(.acquire),
            .state = self.state.load(.acquire),
        };
    }

    pub fn writtenBytes(self: *const MmapSpool) usize {
        return self.offset;
    }

    pub fn flush(self: *MmapSpool, boundary: types.Flush) !void {
        if (boundary == .durable) return error.UnsupportedDurability;
        if (self.last_error.load(.acquire) != 0) return error.DeliveryFailed;
        // Publish the exact tail before the writer is asked to observe it.
        self.published.store(self.offset, .release);
        if (self.worker == null) {
            self.syncTo(self.published.load(.acquire)) catch |err| return err;
            return;
        }
        const observed = self.flush_epoch.load(.seq_cst);
        self.flush_requested.store(true, .release);
        self.wake();
        while (self.flush_epoch.load(.seq_cst) == observed) {
            if (self.state.load(.acquire) == .closed) break;
            self.io.futexWaitUncancelable(u32, &self.flush_epoch.raw, observed);
        }
        if (self.last_error.load(.acquire) != 0) return error.DeliveryFailed;
    }

    pub fn shutdown(self: *MmapSpool) !void {
        if (self.worker) |thread| {
            self.state.store(.closing, .release);
            self.wake();
            thread.join();
            self.worker = null;
        }
        self.state.store(.closed, .release);
        const offset = self.published.load(.acquire);
        self.syncTo(offset) catch {};
        // Publish exactly the rendered bytes. The mapping stays alive until
        // deinit; no page beyond the new length is touched.
        self.mapping.file.setLength(self.io, offset) catch |err| {
            self.recordError(err);
        };
        if (self.last_error.load(.acquire) != 0) return error.DeliveryFailed;
    }

    // Logger owner interface.
    pub fn enabled(self: *MmapSpool, level: Level, _: []const u8) bool {
        return self.state.load(.acquire) == .running and self.min_level.allows(level);
    }

    pub fn begin(self: *MmapSpool, level: Level, _: []const u8) LoggerModule.BeginResult {
        if (self.state.load(.acquire) != .running) return .closed;
        if (!self.min_level.allows(level)) return .filtered;
        return .{ .ready = .{ .route_mask = 1, .config_generation = 1 } };
    }

    pub fn end(self: *MmapSpool) void {
        _ = self;
    }

    pub fn endAdmission(self: *MmapSpool, _: LoggerModule.Admission) void {
        _ = self;
    }

    pub fn nowNs(self: *MmapSpool) i64 {
        if (self.timestamp_period <= 1) return self.clock.realNow(self.io);
        if (self.timestamp_counter == 0) self.cached_now = self.clock.realNow(self.io);
        self.timestamp_counter += 1;
        if (self.timestamp_counter == self.timestamp_period) self.timestamp_counter = 0;
        return self.cached_now;
    }

    pub fn captureFailed(self: *MmapSpool, err: anyerror) void {
        self.recordError(err);
    }

    pub fn submit(self: *MmapSpool, _: LoggerModule.Admission, event: Event) !LoggerModule.EmitResult {
        if (self.state.load(.acquire) != .running) return .rejected_closing;
        if (self.last_error.load(.acquire) != 0) return error.DeliveryFailed;
        if (self.offset == self.mapping.bytes.len) {
            self.dropped_full += 1;
            return .dropped_full;
        }
        var submitted = event;
        submitted.session = self.session;
        self.sequence += 1;
        submitted.sequence = self.sequence;
        var writer = std.Io.Writer.fixed(self.mapping.bytes[self.offset..]);
        common.encodeDecodedPtr(.json, &submitted, self.timestamp, &writer) catch |err| {
            if (err == error.WriteFailed) {
                self.dropped_oversize += 1;
                return .dropped_oversize;
            }
            self.recordError(err);
            return err;
        };
        self.offset += writer.buffered().len;
        self.published.store(self.offset, .release);
        self.accepted += 1;
        self.written += 1;
        if (self.worker != null and self.offset - self.synced.load(.monotonic) >= sync_threshold) self.wake();
        return .accepted;
    }

    fn recordError(self: *MmapSpool, err: anyerror) void {
        _ = self.errors.fetchAdd(1, .monotonic);
        self.last_error.store(@intFromError(err), .release);
    }

    fn wake(self: *MmapSpool) void {
        _ = self.wake_epoch.fetchAdd(1, .seq_cst);
        if (self.worker_sleeping.load(.seq_cst)) self.io.futexWake(u32, &self.wake_epoch.raw, std.math.maxInt(u32));
    }

    fn syncTo(self: *MmapSpool, target: usize) !void {
        const from = self.synced.load(.monotonic);
        if (target <= from) return;
        self.mapping.syncMappedRangeAsync(from, target) catch |err| {
            self.recordError(err);
            return err;
        };
        self.synced.store(target, .release);
    }

    fn workerMain(self: *MmapSpool) void {
        while (true) {
            const published = self.published.load(.acquire);
            if (published - self.synced.load(.monotonic) >= sync_threshold) {
                self.syncTo(published) catch {};
                continue;
            }
            if (self.flush_requested.swap(false, .acq_rel)) {
                self.syncTo(published) catch {};
                _ = self.flush_epoch.fetchAdd(1, .release);
                self.io.futexWake(u32, &self.flush_epoch.raw, std.math.maxInt(u32));
                continue;
            }
            if (self.state.load(.acquire) == .closing) {
                self.syncTo(self.published.load(.acquire)) catch {};
                _ = self.flush_epoch.fetchAdd(1, .release);
                self.io.futexWake(u32, &self.flush_epoch.raw, std.math.maxInt(u32));
                self.state.store(.closed, .release);
                return;
            }
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
};

test "mmap spool output matches durable deferred render" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    const runtime_mod = @import("runtime.zig");
    const memory_mod = @import("../sink/memory.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/spool.log", .{tmp.sub_path});
    const spool_bytes = spoolRun(std.testing.allocator, path, tmp.dir) catch |err| switch (err) {
        error.VolatileFilesystem => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(spool_bytes);
    var durable_buffer: [16 * 1024]u8 = undefined;
    var sink = memory_mod.MemorySink.initBuffer(&durable_buffer);
    const runtime = try runtime_mod.Runtime.create(std.testing.allocator, std.testing.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 1024, .verify_crc = false, .text_format = true },
        .routes = &.{.{ .name = "cache", .sink = sink.sink(), .format = .json }},
        .clock = Clock.zeroTimestamp(),
    });
    defer runtime.destroy();
    runtime.session = 42;
    const log = runtime.scoped("cache");
    for (0..4) |index| _ = try log.tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    try std.testing.expectEqualStrings(sink.written(), spool_bytes);
}

fn spoolRun(allocator: std.mem.Allocator, path: []const u8, dir: std.Io.Dir) ![]u8 {
    const spool = try MmapSpool.create(allocator, std.testing.io, .{
        .path = path,
        .capacity_bytes = 64 * 1024,
        .clock = Clock.zeroTimestamp(),
        .session = 42,
    });
    defer spool.destroy();
    const log = spool.logger("cache");
    for (0..4) |index| _ = try log.tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
    try spool.flush(.written);
    try spool.shutdown();
    return dir.readFileAlloc(std.testing.io, "spool.log", allocator, .limited(64 * 1024));
}

test "mmap spool stops at capacity without publishing a partial record" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/spool-cap.log", .{tmp.sub_path});
    const spool = MmapSpool.create(std.testing.allocator, std.testing.io, .{
        .path = path,
        .capacity_bytes = 1024,
        .clock = Clock.zeroTimestamp(),
        .session = 42,
    }) catch |err| switch (err) {
        error.VolatileFilesystem => return error.SkipZigTest,
        else => return err,
    };
    defer spool.destroy();
    const log = spool.logger("cache");
    var accepted: usize = 0;
    while (accepted < 64) {
        const result = log.tryEmit(.info, "inline", .{ .n = @as(u64, accepted), .s = "x" }) catch |err| switch (err) {
            error.DeliveryFailed => break,
            else => return err,
        };
        switch (result) {
            .accepted => accepted += 1,
            .dropped_full, .dropped_oversize => break,
            else => break,
        }
    }
    try spool.flush(.written);
    try spool.shutdown();
    const health = spool.health();
    try std.testing.expect(accepted > 0);
    try std.testing.expect(health.dropped_full + health.dropped_oversize > 0);
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "spool-cap.log", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(bytes.len <= 1024);
    try std.testing.expect(std.mem.endsWith(u8, bytes, "\n"));
    var lines: usize = 0;
    for (bytes) |byte| if (byte == '\n') {
        lines += 1;
    };
    try std.testing.expectEqual(accepted, lines);
}

test "mmap spool timestamp period reuses a capture" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    const Counter = struct {
        var calls: usize = 0;
        fn now(_: ?*anyopaque, _: std.Io) i64 {
            calls += 1;
            return @intCast(calls);
        }
    };
    Counter.calls = 0;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/spool-ts.log", .{tmp.sub_path});
    const spool = MmapSpool.create(std.testing.allocator, std.testing.io, .{
        .path = path,
        .capacity_bytes = 16 * 1024,
        .clock = .{ .real_now = Counter.now },
        .session = 42,
        .timestamp_period = 4,
    }) catch |err| switch (err) {
        error.VolatileFilesystem => return error.SkipZigTest,
        else => return err,
    };
    defer spool.destroy();
    const log = spool.logger("cache");
    for (0..8) |index| _ = try log.tryEmit(.info, "inline", .{ .n = @as(u64, index), .s = "x" });
    try spool.flush(.written);
    try spool.shutdown();
    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "spool-ts.log", std.testing.allocator, .limited(16 * 1024));
    defer std.testing.allocator.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var expected: i64 = 1;
    var index: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
        const timestamp = parsed.value.object.get("timestamp_ns") orelse return error.MissingTimestamp;
        const value: i64 = switch (timestamp) {
            .integer => |v| v,
            .string => |v| try std.fmt.parseInt(i64, v, 10),
            else => return error.InvalidTimestamp,
        };
        if (index % 4 == 0 and index != 0) expected += 1;
        try std.testing.expectEqual(expected, value);
        index += 1;
    }
    try std.testing.expectEqual(@as(usize, 8), index);
    try std.testing.expectEqual(@as(usize, 2), Counter.calls);
}
