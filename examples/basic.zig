const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const file = try kron.FileSink.create(allocator, io, .{ .path = "kron-example.jsonl" });
    defer file.deinit();
    var stderr_buffer: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    var console = kron.WriterSink.init(&stderr.interface);
    const environment = kron.environment.merge(.{
        .environment = kron.environment.fromMap(init.environ_map),
    });
    const runtime = try kron.Runtime.create(allocator, io, .{
        .submission = .asynchronous,
        .journal = .{ .path = "kron-example.journal", .capacity = 256, .max_record_bytes = 8192 },
        .filter = environment.filter_spec,
        .routes = &.{
            .{ .name = "console", .sink = console.sink(), .format = .text, .delivery = .best_effort },
            .{ .name = "file", .sink = file.sink(), .format = .json },
        },
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();

    const log = runtime.scoped("http.server").withBorrowed(.{ .service = "example", .request_id = "req-42" });
    log.info("request accepted", .{ .method = "GET", .password = "do-not-record" });
    log.logf(.info, "response {d} in {d}ns", .{ 200, 1234 }, .{
        .status = @as(u16, 200),
        .latency = kron.durationNs(1234),
        .token = kron.secret("do-not-record"),
    });
    try runtime.reloadFilter("warn,http.server=debug");
    log.debug("dynamic filter enabled debug", .{});
    try runtime.flush(.durable);
    try runtime.shutdown(.drain);
}
