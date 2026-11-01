const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const old_file = try kron.FileSink.create(init.gpa, init.io, .{ .path = "kron-before.jsonl" });
    defer old_file.deinit();
    const new_file = try kron.FileSink.create(init.gpa, init.io, .{ .path = "kron-after.jsonl" });
    defer new_file.deinit();
    const archive_file = try kron.FileSink.create(init.gpa, init.io, .{ .path = "kron-compressed.kron", .buffer_bytes = 256 * 1024 });
    defer archive_file.deinit();
    const archive = try kron.CompressedArchiveSink.create(init.gpa, .{ .sink = archive_file.sink() });
    defer archive.deinit();
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .journal = .{ .path = "kron-hot.journal", .capacity = 64, .max_record_bytes = 8192 },
        .routes = &.{.{ .name = "file", .sink = old_file.sink() }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    const log = runtime.scoped("http.server");
    log.info("before replacement", .{ .password = "never record" });
    _ = try runtime.replaceConfiguration(&.{
        .{ .name = "file", .sink = new_file.sink() },
        .{ .name = "archive", .sink = archive.sink(), .format = .binary },
    }, .{
        .default_filter = "info,http.server=debug",
        .redaction = &.{.{ .key = "password", .action = .drop }},
    });
    const attributes = [_]kron.Field{ kron.kv("method", "GET"), kron.kv("password", "never record"), kron.kv("status", @as(u16, 200)) };
    const values = [_]kron.Value{ kron.fields.fromAny(kron.group(&attributes)), kron.fields.fromAny(@as(u64, 42)) };
    log.debug("after replacement", .{ .requests = kron.array(&values) });
    try runtime.flushUntil(.durable, kron.Deadline.after(init.io, 5 * std.time.ns_per_s));
    _ = try runtime.collectConfigurations();
    try runtime.shutdownUntil(kron.Deadline.after(init.io, 5 * std.time.ns_per_s));
}
