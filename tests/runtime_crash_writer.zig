//! Child workload for random-time SIGKILL, without capture/delivery fault hooks.
//! ACK follows a successful public emit; the parent accepts one unacknowledged
//! in-flight event per producer. READY only establishes a written warm prefix.
const std = @import("std");
const kron = @import("kron");

const producer_count = 2;
const warm_records = 64;
const raw_password = "kron-random-crash-private-82dbdc07";
const scope = "crash.random";
const template = "producer {[producer]d} event {[id]d}: {[payload]s}";
const source: std.builtin.SourceLocation = .{
    .module = "random.crash.owner",
    .file = "runtime_crash_writer.zig",
    .fn_name = "emitSnapshot",
    .line = 100,
    .column = 1,
};
const Mode = enum { shared, spsc };
const Args = struct { producer: u32, id: u64, payload: []const u8 };
const Fields = struct { seed: u64, producer: u32, id: u64, payload: []const u8, nested: kron.fields.Group, password: []const u8 };

const Shared = struct {
    runtime: *kron.Runtime,
    io: std.Io,
    seed: u64,
    mode: Mode,
    schema: bool,
    output_mutex: std.Io.Mutex = .init,
    start: std.Io.Event = .unset,
    stop: std.atomic.Value(bool) = .init(false),

    fn announce(self: *Shared, bytes: []const u8) !void {
        self.output_mutex.lockUncancelable(self.io);
        defer self.output_mutex.unlock(self.io);
        try std.Io.File.stdout().writeStreamingAll(self.io, bytes);
    }
};

const Producer = struct {
    shared: *Shared,
    index: u32,
    warmed: std.Io.Event = .unset,

    fn main(self: *Producer) void {
        self.run() catch |err| {
            std.debug.print("random crash producer failed: {s}\n", .{@errorName(err)});
            // This executable is only a child fault workload. Exit errors
            // promptly instead of leaving the parent waiting for READY.
            std.process.exit(1);
        };
    }

    fn run(self: *Producer) !void {
        const runtime = self.shared.runtime;
        if (self.shared.mode == .spsc) {
            const base = try runtime.attachThread(.{ .scope = scope });
            defer base.detach() catch {};
            if (self.shared.schema) {
                const binding = try runtime.prewarmThreadSchema(@intCast(base.owner.control_index + 1), event_shape);
                try self.produce(try runtime.threadLoggerWithSchema(base, binding));
            } else try self.produce(base);
        } else if (self.shared.schema) {
            try self.produce(try runtime.loggerWithSchema(try runtime.prewarmSchema(event_shape)));
        } else try self.produce(runtime.scoped(scope));
    }

    fn produce(self: *Producer, log: anytype) !void {
        for (0..warm_records) |identifier| try self.emitSnapshot(log, identifier);
        self.warmed.set(self.shared.io);
        self.shared.start.waitUncancelable(self.shared.io);
        var identifier: u64 = warm_records;
        while (!self.shared.stop.load(.acquire)) : (identifier += 1) {
            if (identifier >= 20000) return error.ParentDidNotKillWorkload;
            try self.emitSnapshot(log, identifier);
            // Vary producer/worker overlap without trapping either thread at
            // a known reservation or commit boundary. Not a benchmark.
            if (identifier % 8 == self.index) try std.Io.sleep(self.shared.io, .fromNanoseconds(50000), .awake);
        }
    }

    fn emitSnapshot(self: *Producer, log: anytype, identifier: u64) !void {
        var payload_bytes: [1024]u8 = undefined;
        const length: usize = @intCast(64 + (self.shared.seed % 897 + identifier * 17 + self.index * 31) % 897);
        @memset(payload_bytes[0..length], @as(u8, 'a') + @as(u8, @intCast((identifier + self.index) % 26)));
        var label_bytes: [96]u8 = undefined;
        const label = try std.fmt.bufPrint(&label_bytes, "child-{d}-{d}-{d}", .{ self.shared.seed, self.index, identifier });
        var label_key = "label".*;
        var bytes = [_]u8{ @truncate(identifier), @truncate(self.shared.seed), @truncate(self.index), 255 };
        var values = [_]kron.Value{ .{ .unsigned = identifier }, .{ .boolean = identifier % 2 == 0 }, kron.fields.fromAny(kron.bytes(&bytes)), .null_value };
        var members = [_]kron.Field{
            kron.kv(label_key[0..], label), kron.kv("values", kron.array(&values)), kron.kv("secret", kron.secret(raw_password)),
        };
        const payload = payload_bytes[0..length];
        const fields: Fields = .{ .seed = self.shared.seed, .producer = self.index, .id = identifier, .payload = payload, .nested = kron.group(&members), .password = raw_password };
        if (try log.tryLogfAt(source, .info, template, Args{ .producer = self.index, .id = identifier, .payload = payload }, fields) != .accepted) return error.EventNotAccepted;
        @memset(&payload_bytes, 'x');
        @memset(&label_bytes, 'x');
        @memset(&label_key, 'x');
        @memset(&bytes, 0xee);
        values = @splat(.null_value);
        members = @splat(.{ .key = "erased", .value = .null_value });
        std.mem.doNotOptimizeAway(&payload_bytes);
        std.mem.doNotOptimizeAway(&label_bytes);
        std.mem.doNotOptimizeAway(&label_key);
        std.mem.doNotOptimizeAway(&bytes);
        std.mem.doNotOptimizeAway(&values);
        std.mem.doNotOptimizeAway(&members);
        var line: [80]u8 = undefined;
        try self.shared.announce(try std.fmt.bufPrint(&line, "ACK {d} {d}\n", .{ self.index, identifier }));
    }
};

// Static backing is required: an Event borrows its metadata slices.
const event_shape: kron.Event = .{
    .level = .info,
    .scope = scope,
    .source = source,
    .message = template,
    .message_template = true,
    .format_args = &.{ kron.kv("producer", @as(u32, 0)), kron.kv("id", @as(u64, 0)), kron.kv("payload", "shape") },
    .fields = &.{ kron.kv("seed", @as(u64, 0)), kron.kv("producer", @as(u32, 0)), kron.kv("id", @as(u64, 0)), kron.kv("payload", "shape"), kron.kv("nested", kron.group(&.{})), kron.kv("password", raw_password) },
    .timestamp_ns = 0,
};

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len != 6) return error.ExpectedJournalOutputModeSchemaSeed;
    const mode = std.meta.stringToEnum(Mode, arguments[3]) orelse return error.InvalidMode;
    const schema = if (std.mem.eql(u8, arguments[4], "true")) true else if (std.mem.eql(u8, arguments[4], "false")) false else return error.InvalidSchema;
    const seed = try std.fmt.parseInt(u64, arguments[5], 10);
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = arguments[2], .backend = .portable, .buffer_bytes = 8192 });
    defer file.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = if (mode == .spsc) .low_latency else .asynchronous,
        .journal = .{ .path = arguments[1], .capacity = 16, .max_record_bytes = 4096, .schema_capacity = if (schema) 4 else 0, .max_schema_bytes = 4096 },
        .max_thread_channels = if (mode == .spsc) producer_count else 0,
        .thread_channel_capacity = 16,
        .idle = .sleep,
        .routes = &.{.{ .name = "output", .sink = file.sink(), .format = .json }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    var shared: Shared = .{ .runtime = runtime, .io = init.io, .seed = seed, .mode = mode, .schema = schema };
    var producers: [producer_count]Producer = undefined;
    var threads: [producer_count]std.Thread = undefined;
    var started: usize = 0;
    defer {
        shared.stop.store(true, .release);
        shared.start.set(init.io);
        for (threads[0..started]) |thread| thread.join();
    }
    for (&producers, 0..) |*producer, index| {
        producer.* = .{ .shared = &shared, .index = @intCast(index) };
        threads[index] = try std.Thread.spawn(.{}, Producer.main, .{producer});
        started += 1;
    }
    for (&producers) |*producer| producer.warmed.waitUncancelable(init.io);
    try runtime.flush(.written);
    const health = runtime.health();
    if (health.accepted != producer_count * warm_records or health.written != producer_count * warm_records or health.journal_pending != 0) return error.IncompleteWarmPrefix;
    var line: [512]u8 = undefined;
    try shared.announce(try std.fmt.bufPrint(&line, "READY {{\"seed\":{d},\"mode\":\"{s}\",\"schema\":{},\"session\":{d},\"producers\":{d},\"warm_records\":{d}}}\n", .{ seed, @tagName(mode), schema, runtime.session, producer_count, warm_records }));
    shared.start.set(init.io);
    var byte: [1]u8 = undefined;
    _ = try std.Io.File.stdin().readStreaming(init.io, &.{&byte});
    return error.ExpectedSigkill;
}
