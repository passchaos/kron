//! Bounded slow-sink probe: measures producer emit latency under a deliberately
//! slow consumer for block/drop/fallback overflow policies. This is diagnostic
//! evidence, not a product benchmark.
const std = @import("std");
const kron = @import("kron");

const SlowSink = struct {
    io: std.Io,
    delay_ns: u64,
    records: usize = 0,
    bytes: usize = 0,

    fn writeRecord(context: *anyopaque, record: []const u8) anyerror!void {
        const self: *SlowSink = @ptrCast(@alignCast(context));
        std.Io.sleep(self.io, .fromNanoseconds(self.delay_ns), .awake) catch {};
        self.records += 1;
        self.bytes += record.len;
    }

    fn flush(_: *anyopaque) anyerror!void {}

    fn sync(_: *anyopaque) anyerror!void {
        return error.UnsupportedDurability;
    }

    const vtable = kron.Sink.VTable{ .writeRecord = writeRecord, .flush = flush, .sync = sync };

    fn sink(self: *SlowSink) kron.Sink {
        return .{ .context = self, .vtable = &vtable };
    }
};

const Producer = struct {
    runtime: *kron.Runtime,
    io: std.Io,
    id: usize,
    events: usize,
    samples: []u64,
    accepted: usize = 0,
    dropped: usize = 0,
    failure: ?anyerror = null,

    fn run(self: *Producer) void {
        const log = self.runtime.scoped("slow");
        for (0..self.events) |index| {
            const n = self.id * self.events + index;
            const start = std.Io.Clock.awake.now(self.io);
            const result = log.tryEmit(.info, "event", .{
                .field0 = @as(u64, @intCast(n)),
                .field1 = @as(u64, @intCast(n + 1)),
                .field2 = @as(u64, @intCast(n + 2)),
                .field3 = @as(u64, @intCast(n + 3)),
                .field4 = @as(u64, @intCast(n + 4)),
            });
            self.samples[index] = @intCast(start.durationTo(std.Io.Clock.awake.now(self.io)).toNanoseconds());
            const outcome = result catch |err| {
                self.failure = err;
                return;
            };
            switch (outcome) {
                .accepted => self.accepted += 1,
                .dropped_full => self.dropped += 1,
                .filtered, .sampled, .rejected_closing, .dropped_oversize => {},
            }
        }
    }
};

const OverflowChoice = enum { block, drop_newest, fallback_sync };

fn parseOverflow(text: []const u8) !OverflowChoice {
    if (std.mem.eql(u8, text, "block")) return .block;
    if (std.mem.eql(u8, text, "drop")) return .drop_newest;
    if (std.mem.eql(u8, text, "fallback")) return .fallback_sync;
    return error.InvalidOverflow;
}

fn percentile(sorted: []const u64, p: usize) u64 {
    if (sorted.len == 0) return 0;
    const index = @min(sorted.len - 1, (p * sorted.len) / 100);
    return sorted[index];
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return error.ExpectedOverflowProducersEventsDelay;
    const overflow = try parseOverflow(args[1]);
    const producers = try std.fmt.parseInt(usize, args[2], 10);
    const total_events = try std.fmt.parseInt(usize, args[3], 10);
    const delay_ns = try std.fmt.parseInt(u64, args[4], 10);
    if (producers == 0 or producers > 16 or total_events == 0 or delay_ns == 0) return error.InvalidOptions;

    var slow = SlowSink{ .io = io, .delay_ns = delay_ns };
    const runtime = try kron.Runtime.create(allocator, io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 64, .max_record_bytes = 512 },
        .overflow = switch (overflow) {
            .block => .block,
            .drop_newest => .drop_newest,
            .fallback_sync => .fallback_sync,
        },
        .routes = &.{.{ .name = "slow", .sink = slow.sink() }},
    });
    defer runtime.destroy();

    const per_producer = total_events / producers;
    if (per_producer == 0) return error.TooFewEvents;
    const producer_storage = try allocator.alloc(Producer, producers);
    defer allocator.free(producer_storage);
    const sample_storage = try allocator.alloc(u64, per_producer * producers);
    defer allocator.free(sample_storage);
    const threads = try allocator.alloc(std.Thread, producers);
    defer allocator.free(threads);

    const started = std.Io.Clock.awake.now(io);
    for (0..producers) |index| {
        producer_storage[index] = .{
            .runtime = runtime,
            .io = io,
            .id = index,
            .events = per_producer,
            .samples = sample_storage[index * per_producer ..][0..per_producer],
        };
        threads[index] = try std.Thread.spawn(.{}, Producer.run, .{&producer_storage[index]});
    }
    for (threads) |thread| thread.join();
    const producer_elapsed: u64 = @intCast(started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
    for (producer_storage) |producer| if (producer.failure) |err| return err;

    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    const total_elapsed: u64 = @intCast(started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
    const health = runtime.health();
    std.mem.sort(u64, sample_storage, {}, std.sort.asc(u64));
    var accepted: usize = 0;
    var dropped: usize = 0;
    for (producer_storage) |producer| {
        accepted += producer.accepted;
        dropped += producer.dropped;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    try stdout.interface.print(
        "{{\"overflow\":\"{s}\",\"producers\":{d},\"events\":{d},\"delay_ns\":{d},\"accepted\":{d},\"dropped_full\":{d},\"written\":{d},\"sink_records\":{d},\"sink_bytes\":{d},\"producer_elapsed_ns\":{d},\"total_elapsed_ns\":{d},\"p50_ns\":{d},\"p99_ns\":{d},\"max_ns\":{d},\"journal_high_water\":{d}}}\n",
        .{ args[1], producers, total_events, delay_ns, accepted, dropped, health.written, slow.records, slow.bytes, producer_elapsed, total_elapsed, percentile(sample_storage, 50), percentile(sample_storage, 99), percentile(sample_storage, 100), health.journal_high_water },
    );
    try stdout.interface.flush();
}
