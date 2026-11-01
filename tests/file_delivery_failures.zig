//! Real portable FileSink delivery with deterministic positional write faults.
//! Successful prefixes really reach the file. Recovery explicitly recreates
//! the output; Runtime never repairs or truncates a partial destination itself.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");
const testing = std.testing;

const Mode = enum { no_space, write_zero, complete_short_writes };
const Fault = struct {
    var active: ?*Fault = null;
    mode: Mode,
    prefix_bytes: usize = 7,
    calls: std.atomic.Value(usize) = .init(0),
    offsets: [128]u64 = @splat(0),

    fn write(userdata: ?*anyopaque, file: std.Io.File, header: []const u8, data: []const []const u8, splat: usize, offset: u64) std.Io.File.WritePositionalError!usize {
        const self = active.?;
        const call = self.calls.fetchAdd(1, .monotonic);
        if (call >= self.offsets.len) return error.InputOutput;
        self.offsets[call] = offset;
        if (header.len != 0 or data.len != 1 or splat != 1) return error.InputOutput;
        if (self.mode != .complete_short_writes and (call != 0 or self.prefix_bytes == 0)) {
            if (self.mode == .no_space) return error.NoSpaceLeft;
            return 0;
        }
        const prefix = data[0][0..@min(self.prefix_bytes, data[0].len)];
        return testing.io.vtable.fileWritePositional(userdata, file, &.{}, &.{prefix}, 1, offset);
    }

    fn install(self: *Fault, vtable: *std.Io.VTable) std.Io {
        active = self;
        vtable.* = testing.io.vtable.*;
        vtable.fileWritePositional = write;
        return .{ .userdata = testing.io.userdata, .vtable = vtable };
    }

    fn expected(self: *const Fault) anyerror {
        return if (self.mode == .no_space) error.NoSpaceLeft else error.WriteZero;
    }
};

fn journalPath(tmp: *const testing.TmpDir, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/delivery.journal", .{tmp.sub_path});
}

fn checkRetained(runtime: *kron.Runtime) !void {
    // shutdown joined the collector before this test assumes peek ownership.
    const journal = runtime.journal.?;
    try testing.expectEqual(@as(usize, 1), journal.pending());
    try testing.expectEqual(@as(u64, 0), journal.writtenTarget());
    const record = (try journal.peekChecked()).?; // Actual length/generation/CRC validation.
    try testing.expectEqual(@as(u64, 1), record.sequence);
    try testing.expectEqual(@as(u64, 1), record.generation);
    const offset = 4096 + record.slot * journal.stride;
    const header = journal.mapping.bytes[offset..][0..64];
    try testing.expectEqual(@as(u64, 6), std.mem.readInt(u64, header[0..8], .little)); // seq 1, committed.
    try testing.expectEqual(@as(u32, @intCast(record.payload.len)), std.mem.readInt(u32, header[24..28], .little));
    var fields: [8]kron.Field = undefined;
    const event = try kron.codec.decode(record.payload, &fields);
    try testing.expectEqual(@as(u64, 1), event.sequence);
    try testing.expectEqualStrings("complete journal event", event.message);
    try testing.expectEqualStrings("[REDACTED]", event.fields[1].value.string);
}

fn requiredFailure(mode: Mode, prefix_bytes: usize, append_prefix: []const u8, replay: bool) !void {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    if (append_prefix.len != 0) {
        const existing = try tmp.dir.createFile(testing.io, "output.jsonl", .{});
        defer existing.close(testing.io);
        try existing.writePositionalAll(testing.io, append_prefix, 0);
    }
    var path_buffer: [128]u8 = undefined;
    const path = try journalPath(&tmp, &path_buffer);
    var fault: Fault = .{ .mode = mode, .prefix_bytes = prefix_bytes };
    var vtable: std.Io.VTable = undefined;
    const io = fault.install(&vtable);
    defer Fault.active = null;
    var output_owner: ?*kron.FileSink = try kron.FileSink.create(testing.allocator, io, .{ .path = "output.jsonl", .dir = tmp.dir, .backend = .portable, .buffer_bytes = 8192 });
    defer if (output_owner) |output| output.deinit();
    const output = output_owner.?;
    const identity = try testing.allocator.dupe(u8, output.sink().recovery_identity.?);
    defer testing.allocator.free(identity);
    var runtime_owner: ?*kron.Runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 2048 },
        .routes = &.{.{ .name = "file", .sink = output.sink() }},
    });
    defer if (runtime_owner) |runtime| runtime.destroy();
    const runtime = runtime_owner.?;
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("file.failure").tryEmit(.info, "complete journal event", .{ .answer = 42, .secret = kron.secret("raw-secret") }));
    try testing.expectError(fault.expected(), runtime.flush(.written));
    try testing.expectError(fault.expected(), runtime.shutdown(.drain));
    const health = runtime.health();
    try testing.expectEqual(@as(u64, 1), health.accepted);
    try testing.expectEqual(@as(u64, 0), health.written);
    try testing.expectEqual(@as(u64, 0), health.write_errors);
    try testing.expectEqual(@as(u64, 1), health.flush_errors);
    try testing.expectEqual(@as(u64, 0), health.sync_errors);
    try testing.expectEqual(fault.expected(), health.last_error.?);
    try testing.expectEqual(.closed, health.state);
    try testing.expect(!health.worker_alive);
    try testing.expectEqual(fault.expected(), output.failure.?);
    try testing.expectEqual(@as(u64, @intCast(append_prefix.len + prefix_bytes)), output.writtenBytes());
    const accepted_bytes = output.acceptedBytes();
    try testing.expect(accepted_bytes > output.writtenBytes());
    const expected_calls: usize = if (prefix_bytes == 0) 1 else 2;
    try testing.expectEqual(expected_calls, fault.calls.load(.acquire));
    try testing.expectEqual(@as(u64, @intCast(append_prefix.len)), fault.offsets[0]);
    if (prefix_bytes != 0) try testing.expectEqual(@as(u64, @intCast(append_prefix.len + prefix_bytes)), fault.offsets[1]);
    try checkRetained(runtime);
    var retained_header: [64]u8 = undefined;
    @memcpy(&retained_header, runtime.journal.?.mapping.bytes[4096..][0..64]);
    var retained_payload: [2048]u8 = undefined;
    const record = (try runtime.journal.?.peekChecked()).?;
    @memcpy(retained_payload[0..record.payload.len], record.payload);
    const partial = try tmp.dir.readFileAlloc(testing.io, "output.jsonl", testing.allocator, .limited(8192));
    defer testing.allocator.free(partial);
    try testing.expectEqual(append_prefix.len + prefix_bytes, partial.len);
    try testing.expectEqualSlices(u8, append_prefix, partial[0..append_prefix.len]);
    try testing.expectEqualSlices(u8, output.buffer[0..prefix_bytes], partial[append_prefix.len..]);
    try testing.expectError(fault.expected(), runtime.flush(.written));
    try testing.expectError(fault.expected(), output.flush());
    try testing.expectError(fault.expected(), output.writeRecord("must not append"));
    try testing.expectError(fault.expected(), runtime.shutdown(.drain));
    try testing.expectError(fault.expected(), output.shutdown());
    try testing.expectEqual(expected_calls, fault.calls.load(.acquire));
    try testing.expectEqual(accepted_bytes, output.acceptedBytes());
    try testing.expectEqualSlices(u8, &retained_header, runtime.journal.?.mapping.bytes[4096..][0..64]);
    try testing.expectEqualSlices(u8, retained_payload[0..record.payload.len], (try runtime.journal.?.peekChecked()).?.payload);
    if (!replay) return;
    runtime.destroy();
    runtime_owner = null;
    output.deinit();
    output_owner = null;
    try testing.expectEqual(expected_calls, fault.calls.load(.acquire));
    // Explicit application decision: discard the partial output after all
    // owners are stopped. FileSink/Runtime did not silently repair that file.
    const repaired = try kron.FileSink.create(testing.allocator, testing.io, .{ .path = "output.jsonl", .dir = tmp.dir, .backend = .portable, .buffer_bytes = 8192, .append = false });
    defer repaired.deinit();
    try testing.expectEqualStrings(identity, repaired.sink().recovery_identity.?);
    const recovered = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = path, .capacity = 4, .max_record_bytes = 2048 },
        .routes = &.{.{ .name = "file", .sink = repaired.sink() }},
    });
    defer recovered.destroy();
    try recovered.flush(.written);
    try testing.expectEqual(@as(u64, 1), recovered.health().recovered);
    try testing.expectEqual(@as(u64, 1), recovered.health().written);
    try testing.expectEqual(@as(usize, 0), recovered.health().journal_pending);
    const full = try tmp.dir.readFileAlloc(testing.io, "output.jsonl", testing.allocator, .limited(8192));
    defer testing.allocator.free(full);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, full, "\n"));
    try testing.expect(std.mem.indexOf(u8, full, "raw-secret") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, full, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("complete journal event", parsed.value.object.get("message").?.string);
    try testing.expectEqual(@as(i64, 1), parsed.value.object.get("sequence").?.integer);
    try testing.expectEqual(@as(i64, 42), parsed.value.object.get("attributes").?.object.get("answer").?.integer);
    try testing.expectEqualStrings("[REDACTED]", parsed.value.object.get("attributes").?.object.get("secret").?.string);
}

test "file delivery: partial NoSpaceLeft retains committed record and latches output progress" {
    try requiredFailure(.no_space, 7, "", false);
}

test "file delivery: partial WriteZero preserves successful prefix without retrying it" {
    try requiredFailure(.write_zero, 7, "", false);
}

test "file delivery: appended output retains its initial offset when the first write makes no progress" {
    try requiredFailure(.write_zero, 0, "previous complete line\n", false);
}

test "file delivery: reopening the same binding explicitly discards partial output then replays full record" {
    try requiredFailure(.no_space, 11, "previous complete line\n", true);
}

test "file delivery: successful short writes advance offsets and acknowledge exactly one record" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var fault: Fault = .{ .mode = .complete_short_writes };
    var vtable: std.Io.VTable = undefined;
    const io = fault.install(&vtable);
    defer Fault.active = null;
    const output = try kron.FileSink.create(testing.allocator, io, .{ .path = "output.jsonl", .dir = tmp.dir, .backend = .portable, .buffer_bytes = 8192 });
    defer output.deinit();
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 2048 },
        .routes = &.{.{ .name = "file", .sink = output.sink() }},
    });
    defer runtime.destroy();
    _ = try runtime.scoped("short").tryEmit(.info, "all short writes complete", .{});
    try runtime.flush(.written);
    const calls = fault.calls.load(.acquire);
    try testing.expect(calls > 1);
    for (fault.offsets[0..calls], 0..) |offset, index| try testing.expectEqual(@as(u64, @intCast(index * fault.prefix_bytes)), offset);
    try testing.expectEqual(output.acceptedBytes(), output.writtenBytes());
    try testing.expectEqual(@as(u64, 1), runtime.health().written);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    const bytes = try tmp.dir.readFileAlloc(testing.io, "output.jsonl", testing.allocator, .limited(8192));
    defer testing.allocator.free(bytes);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "\n"));
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, bytes, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("all short writes complete", parsed.value.object.get("message").?.string);
}

test "file delivery: partial best effort file failure does not block required acknowledgement" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    var fault: Fault = .{ .mode = .no_space };
    var vtable: std.Io.VTable = undefined;
    const io = fault.install(&vtable);
    defer Fault.active = null;
    const output = try kron.FileSink.create(testing.allocator, io, .{ .path = "best-effort.jsonl", .dir = tmp.dir, .backend = .portable, .buffer_bytes = 8192 });
    defer output.deinit();
    var memory_bytes: [8192]u8 = undefined;
    var required = kron.MemorySink.initBuffer(&memory_bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = try journalPath(&tmp, &path_buffer), .capacity = 4, .max_record_bytes = 2048 },
        .routes = &.{
            .{ .name = "best effort", .sink = output.sink(), .delivery = .best_effort },
            .{ .name = "required", .sink = required.sink(), .recovery_identity = "required-test-memory" },
        },
    });
    defer runtime.destroy();
    _ = try runtime.scoped("isolation").tryEmit(.info, "first", .{});
    try runtime.flush(.written);
    try testing.expectEqual(@as(u64, 7), output.writtenBytes());
    try testing.expectEqual(error.NoSpaceLeft, output.failure.?);
    const calls = fault.calls.load(.acquire);
    _ = try runtime.scoped("isolation").tryEmit(.info, "second", .{});
    try runtime.flush(.written);
    try testing.expectEqual(@as(usize, 2), required.records);
    try testing.expectEqual(@as(u64, 2), runtime.health().written);
    try testing.expectEqual(@as(usize, 0), runtime.health().journal_pending);
    try testing.expectEqual(@as(u64, 1), runtime.health().write_errors);
    try testing.expect(runtime.health().flush_errors >= 2);
    try testing.expectEqual(error.NoSpaceLeft, runtime.health().last_error.?);
    try testing.expectEqual(calls, fault.calls.load(.acquire));
    try runtime.shutdown(.drain);
    try testing.expectEqual(calls, fault.calls.load(.acquire));
}
