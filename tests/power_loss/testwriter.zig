//! Executes only inside the scratch VM. The host harness kills QEMU after a
//! completed durable acknowledgement and verifies through a snapshot overlay.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingMode;
    var journal_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var acked: ?u64 = null;
    var schema_enabled = false;
    var index: usize = 2;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len) return error.MissingValue;
        if (std.mem.eql(u8, args[index], "--journal")) journal_path = args[index + 1] else if (std.mem.eql(u8, args[index], "--output")) output_path = args[index + 1] else if (std.mem.eql(u8, args[index], "--acked")) acked = try std.fmt.parseInt(u64, args[index + 1], 10) else if (std.mem.eql(u8, args[index], "--schema")) schema_enabled = std.mem.eql(u8, args[index + 1], "1") else return error.UnknownOption;
    }
    const output = output_path orelse return error.MissingOutput;
    if (std.mem.eql(u8, args[1], "enospc")) return enospc(init, output);
    const journal = journal_path orelse return error.MissingJournal;
    if (std.mem.eql(u8, args[1], "write")) {
        try write(init, journal, output, schema_enabled);
    } else if (std.mem.eql(u8, args[1], "verify")) {
        try verify(init, journal, output, acked orelse return error.MissingAcknowledgement, schema_enabled);
    } else return error.UnknownMode;
}

fn enospc(init: std.process.Init, output_path: []const u8) !void {
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = output_path, .backend = .portable });
    defer file.deinit();
    try file.writeRecord("buffered-before-full\n");
    const runtime_path = try std.fmt.allocPrint(init.gpa, "{s}.runtime", .{output_path});
    defer init.gpa.free(runtime_path);
    const runtime_file = try kron.FileSink.create(init.gpa, init.io, .{ .path = runtime_path, .backend = .portable });
    defer runtime_file.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 8, .max_record_bytes = 512 },
        .overflow = .block,
        .routes = &.{.{ .name = "runtime-file", .sink = runtime_file.sink(), .format = .json }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("enospc");
    const filler_path = try std.fmt.allocPrint(init.gpa, "{s}.filler", .{output_path});
    defer init.gpa.free(filler_path);
    const filler = try std.Io.Dir.cwd().createFile(init.io, filler_path, .{});
    defer filler.close(init.io);
    var chunk: [4096]u8 = @splat('x');
    var offset: u64 = 0;
    while (true) {
        const written = filler.writePositional(init.io, &.{&chunk}, offset) catch |err| switch (err) {
            error.NoSpaceLeft => break,
            else => return err,
        };
        if (written == 0) return error.FillZero;
        offset += written;
    }
    std.debug.print("KRON_ENOSPC_FILLED bytes={d}\n", .{offset});
    file.flush() catch |err| {
        std.debug.print("KRON_ENOSPC_LATCHED err={s}\n", .{@errorName(err)});
        if (try log.tryEmit(.info, "runtime-after-full", .{}) != .accepted) return error.RecordRejected;
        runtime.flush(.durable) catch |runtime_err| {
            std.debug.print("KRON_ENOSPC_RUNTIME_LATCHED err={s}\n", .{@errorName(runtime_err)});
            return;
        };
        std.debug.print("KRON_ENOSPC_RUNTIME_UNEXPECTED\n", .{});
        return error.UnexpectedSuccess;
    };
    std.debug.print("KRON_ENOSPC_UNEXPECTED\n", .{});
    return error.UnexpectedSuccess;
}

fn write(init: std.process.Init, journal_path: []const u8, output_path: []const u8, schema_enabled: bool) !void {
    const file = try kron.FileSink.create(init.gpa, init.io, .{ .path = output_path, .backend = .portable });
    defer file.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = journal_path, .capacity = 16, .max_record_bytes = 2048, .schema_capacity = if (schema_enabled) 16 else 0, .max_schema_bytes = 4096 },
        .routes = &.{.{ .name = "durable-file", .sink = file.sink(), .format = .json, .reclaim_after = .durable }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("power-loss");
    const prepared = if (schema_enabled) try runtime.loggerWithSchema(try runtime.prewarmSchema(.{
        .level = .info,
        .scope = "power-loss",
        .message = "durable power-loss record",
        .fields = &.{ kron.kv("index", @as(u64, 1)), kron.kv("marker", "kron-power-loss-v1"), kron.kv("secret", kron.secret("never persist this value")) },
        .timestamp_ns = 0,
    })) else null;
    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    for (1..257) |number| {
        const values = .{
            .index = @as(u64, @intCast(number)),
            .marker = "kron-power-loss-v1",
            .secret = kron.secret("never persist this value"),
        };
        const result = if (prepared) |ready| try ready.tryEmit(.info, "durable power-loss record", values) else try log.tryEmit(.info, "durable power-loss record", values);
        if (result != .accepted) return error.RecordRejected;
        try runtime.flush(.durable);
        try stdout.interface.print("KRON_ACK seq={d}\n", .{number});
        try stdout.interface.flush();
    }
    while (true) try init.io.sleep(.fromSeconds(1), .awake);
}

fn verify(init: std.process.Init, journal_path: []const u8, output_path: []const u8, acked: u64, schema_enabled: bool) !void {
    if (acked == 0 or acked > 256) return error.InvalidAcknowledgement;
    const output = try std.Io.Dir.cwd().readFileAlloc(init.io, output_path, init.gpa, .limited(16 * 1024 * 1024));
    defer init.gpa.free(output);
    var seen: [256]u8 = @splat(0);
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(std.json.Value, init.gpa, line, .{}) catch |err| {
            // An unacknowledged torn tail is allowed. Every acknowledged record
            // must already have been verified before we encounter it.
            for (seen[0..@intCast(acked)]) |count| if (count == 0) return err;
            break;
        };
        defer parsed.deinit();
        const attributes = parsed.value.object.get("attributes") orelse return error.MissingAttributes;
        const value = attributes.object.get("index") orelse return error.MissingIndex;
        const number: u64 = switch (value) {
            .integer => |integer| std.math.cast(u64, integer) orelse return error.InvalidIndex,
            .number_string, .string => |text| try std.fmt.parseInt(u64, text, 10),
            else => return error.InvalidIndex,
        };
        if (number == 0 or number > seen.len) return error.InvalidIndex;
        if (number <= acked) {
            if (seen[number - 1] != 0) return error.DuplicateAcknowledgedRecord;
            seen[number - 1] = 1;
            const marker = attributes.object.get("marker") orelse return error.MissingMarker;
            if (marker != .string or !std.mem.eql(u8, marker.string, "kron-power-loss-v1")) return error.InvalidMarker;
            const secret = attributes.object.get("secret") orelse return error.MissingRedaction;
            if (secret != .string or !std.mem.eql(u8, secret.string, "[REDACTED]")) return error.InvalidRedaction;
        }
    }
    for (seen[0..@intCast(acked)]) |count| if (count != 1) return error.MissingAcknowledgedRecord;

    // Check the actual durable protocol through Journal recovery; opening is
    // performed only in the VM snapshot overlay, never on the evidence image.
    const journal = try kron.Journal.create(init.gpa, init.io, .{ .path = journal_path, .capacity = 16, .max_record_bytes = 2048, .schema_capacity = if (schema_enabled) 16 else 0, .max_schema_bytes = 4096 });
    defer journal.deinit();
    if (journal.durableReclaimedTarget() < acked) return error.CheckpointBelowAcknowledgement;
    var scratch: [128]kron.Field = undefined;
    while (try journal.peekChecked()) |record| {
        const event = if (record.schema_ref) |reference| try kron.schema_codec.resolve(record.payload, try journal.resolveSchema(reference), &scratch) else try kron.codec.decode(record.payload, &scratch);
        if (event.sequence <= acked) return error.ReplayedDurableAcknowledgement;
        try journal.release(record);
    }
    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    try stdout.interface.print("KRON_CHECKPOINT_OK seq={d} acked={d}\n", .{ journal.durableReclaimedTarget(), acked });
    try stdout.interface.flush();
}
