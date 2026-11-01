//! Seeded workloads stopped at one exact accepted/unwritten boundary. This is
//! process-crash testing across ring wraps and epochs, not arbitrary kill points.
const std = @import("std");
const kron = @import("kron");

const raw_password = "kron-campaign-real-password-f41a7009";
const scope = "recovery.campaign";
const template = "campaign {[id]d}: {[payload]s}";
const source: std.builtin.SourceLocation = .{
    .module = "campaign.owner",
    .file = "recovery_campaign_writer.zig",
    .fn_name = "emitBorrowed",
    .line = 73,
    .column = 5,
};
const Args = struct { id: u64, payload: []const u8 };
const Fields = struct { id: u64, seed: u64, password: []const u8, payload: []const u8, nested: kron.fields.Group, route_generation: u64, route_fingerprint: u64 };
const Released = std.atomic.Value(bool);
const Options = struct {
    seed: u64,
    schema: bool,
    written: usize,
    pending: usize,
    first_replace: usize,
    old_pending: usize,
    journal: []const u8,
    output: []const u8,
};

fn parse(args: []const []const u8) !Options {
    var result: Options = .{ .seed = 0, .schema = false, .written = 0, .pending = 0, .first_replace = 0, .old_pending = 0, .journal = "", .output = "" };
    var seen: u16 = 0;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const split = std.mem.findScalar(u8, args[index], '=');
        const name = if (split) |position| args[index][0..position] else args[index];
        const value = if (split) |position| args[index][position + 1 ..] else blk: {
            index += 1;
            if (index == args.len) return error.MissingArgument;
            break :blk args[index];
        };
        if (value.len == 0) return error.MissingArgument;
        const bit: u16 = if (std.mem.eql(u8, name, "--seed")) blk: {
            result.seed = try std.fmt.parseInt(u64, value, 10);
            break :blk 1;
        } else if (std.mem.eql(u8, name, "--schema")) blk: {
            result.schema = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidSchema;
            break :blk 2;
        } else if (std.mem.eql(u8, name, "--written")) blk: {
            result.written = try std.fmt.parseInt(usize, value, 10);
            break :blk 4;
        } else if (std.mem.eql(u8, name, "--pending")) blk: {
            result.pending = try std.fmt.parseInt(usize, value, 10);
            break :blk 8;
        } else if (std.mem.eql(u8, name, "--first-replace")) blk: {
            result.first_replace = try std.fmt.parseInt(usize, value, 10);
            break :blk 16;
        } else if (std.mem.eql(u8, name, "--old-pending")) blk: {
            result.old_pending = try std.fmt.parseInt(usize, value, 10);
            break :blk 32;
        } else if (std.mem.eql(u8, name, "--journal")) blk: {
            result.journal = value;
            break :blk 64;
        } else if (std.mem.eql(u8, name, "--output")) blk: {
            result.output = value;
            break :blk 128;
        } else return error.UnknownArgument;
        if (seen & bit != 0) return error.DuplicateArgument;
        seen |= bit;
    }
    if (seen != 255 or result.written < 64 or result.written > 127 or result.pending == 0 or result.pending > 7 or result.first_replace < 8 or result.first_replace >= result.written or result.first_replace % 8 != 0 or result.old_pending == 0 or result.old_pending > result.pending) return error.InvalidScenario;
    return result;
}

fn emitBorrowed(runtime: *kron.Runtime, log: anytype, options: Options, identifier: usize) !void {
    var payload_bytes: [80]u8 = undefined;
    var label_bytes: [80]u8 = undefined;
    const payload = try std.fmt.bufPrint(&payload_bytes, "payload-{d}-{d}", .{ options.seed, identifier });
    const label = try std.fmt.bufPrint(&label_bytes, "child-{d}-{d}", .{ options.seed, identifier });
    var label_key = "label".*;
    var values_key = "values".*;
    var bytes = [_]u8{ @truncate(identifier), @truncate(options.seed), @truncate(@as(u64, @intCast(identifier)) ^ options.seed), 0xff };
    var values = [_]kron.Value{ .{ .unsigned = identifier }, .{ .boolean = identifier % 2 == 0 }, kron.fields.fromAny(kron.bytes(&bytes)), .null_value };
    var members = [_]kron.Field{
        kron.kv(label_key[0..], label), kron.kv(values_key[0..], kron.fields.array(&values)), kron.kv("secret", kron.secret(raw_password)),
    };
    // JSON intentionally omits the internal route identity. This single-writer
    // campaign adds actual snapshot probes so written-prefix epochs remain
    // observable after their ring slots have been reclaimed and reused.
    const version = runtime.currentConfiguration();
    const fields: Fields = .{ .id = @intCast(identifier), .seed = options.seed, .password = raw_password, .payload = payload, .nested = kron.fields.group(&members), .route_generation = version.generation, .route_fingerprint = version.fingerprint };
    if (try log.tryLogfAt(source, .info, template, Args{ .id = @intCast(identifier), .payload = payload }, fields) != .accepted) return error.EventNotAccepted;
    @memset(&payload_bytes, 'x');
    @memset(&label_bytes, 'x');
    @memset(&label_key, 'x');
    @memset(&values_key, 'x');
    @memset(&bytes, 0xee);
    for (&values) |*value| value.* = .null_value;
    for (&members) |*member| member.* = .{ .key = "erased", .value = .null_value };
    std.mem.doNotOptimizeAway(&payload_bytes);
    std.mem.doNotOptimizeAway(&label_bytes);
    std.mem.doNotOptimizeAway(&label_key);
    std.mem.doNotOptimizeAway(&values_key);
    std.mem.doNotOptimizeAway(&bytes);
    std.mem.doNotOptimizeAway(&values);
    std.mem.doNotOptimizeAway(&members);
}

fn markReleased(context: *anyopaque) void {
    const flag: *Released = @ptrCast(@alignCast(context));
    flag.store(true, .release);
}

fn replace(runtime: *kron.Runtime, file: *kron.FileSink, generation: u64, released: *Released) !@TypeOf(runtime.currentConfiguration()) {
    const next = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = file.sink(), .format = .json, .release = .{ .context = released, .release = markReleased } }}, .{
        .default_filter = if (generation == 2) "warn,recovery.campaign=info" else "err,recovery.campaign=trace",
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    if (next.generation != generation) return error.UnexpectedGeneration;
    return next;
}

fn run(runtime: *kron.Runtime, file: *kron.FileSink, log: anytype, released: *[3]Released, options: Options, io: std.Io) !void {
    var versions: [3]@TypeOf(runtime.currentConfiguration()) = undefined;
    versions[0] = runtime.currentConfiguration();
    for (0..options.written) |identifier| {
        if (identifier == options.first_replace) {
            try runtime.flush(.written);
            versions[1] = try replace(runtime, file, 2, &released[1]);
            _ = try runtime.collectConfigurations();
        }
        try emitBorrowed(runtime, log, options, identifier);
        if ((identifier + 1) % 8 == 0) try runtime.flush(.written);
    }
    try runtime.flush(.written);
    _ = try runtime.collectConfigurations();
    const collection_deadline = kron.Deadline.after(io, 5 * std.time.ns_per_s);
    while (!released[0].load(.acquire)) {
        if (collection_deadline.expired(io)) return error.WrittenConfigurationNotCollected;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
        _ = try runtime.collectConfigurations();
    }
    const written = runtime.health();
    if (written.accepted != options.written or written.written != options.written or written.journal_pending != 0) return error.UnexpectedWrittenPrefix;
    var gap = try runtime.journal.?.reserve();
    defer gap.abort();
    for (0..options.old_pending) |offset| try emitBorrowed(runtime, log, options, options.written + offset);
    versions[2] = try replace(runtime, file, 3, &released[2]);
    _ = try runtime.collectConfigurations();
    // A missing version also makes configurationReadyToCollect false. The
    // lease callback independently proves generation 2 was not collected.
    if (runtime.configurationReadyToCollect(versions[1]) or released[1].load(.acquire)) return error.OldPendingConfigurationLost;
    for (options.old_pending..options.pending) |offset| try emitBorrowed(runtime, log, options, options.written + offset);
    const health = runtime.health();
    if (health.accepted != options.written + options.pending or health.written != options.written or health.journal_pending != options.pending + 1 or health.last_error != null) return error.UnexpectedPendingBoundary;
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("READY {{\"seed\":{d},\"schema\":{},\"written\":{d},\"pending\":{d},\"queue_pending\":{d},\"accepted\":{d},\"session\":{d},\"first_replace\":{d},\"second_replace\":{d},\"old_pending\":{d},\"first_pending_sequence\":{d},\"old_pending_retained\":true,\"route_fingerprints\":[{d},{d},{d}]}}\n", .{
        options.seed,          options.schema,                        health.written,      options.pending,  health.journal_pending,  health.accepted,         runtime.session,
        options.first_replace, options.written + options.old_pending, options.old_pending, gap.sequence + 1, versions[0].fingerprint, versions[1].fingerprint, versions[2].fingerprint,
    });
    try std.Io.File.stdout().writeStreamingAll(io, writer.buffered());
    var byte: [1]u8 = undefined;
    while (true) if (try std.Io.File.stdin().readStreaming(io, &.{&byte}) == 0) return error.ExpectedSigkill;
}

pub fn main(init: std.process.Init) !void {
    const options = try parse(try init.minimal.args.toSlice(init.arena.allocator()));
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = options.output, .backend = .portable, .buffer_bytes = 8192 });
    defer file.deinit();
    var released: [3]Released = @splat(.init(false));
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = options.journal, .capacity = 16, .max_record_bytes = 4096, .schema_capacity = if (options.schema) 4 else 0, .max_schema_bytes = 4096 },
        .routes = &.{.{ .name = "output", .sink = file.sink(), .format = .json, .release = .{ .context = &released[0], .release = markReleased } }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    if (options.schema) {
        const binding = try runtime.prewarmFormat(scope, source, template, Args, Fields);
        const log = try runtime.loggerWithSchema(binding);
        try run(runtime, file, log, &released, options, init.io);
    } else {
        const log = runtime.logger(.{ .scope = scope });
        try run(runtime, file, log, &released, options, init.io);
    }
}
