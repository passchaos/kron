const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var console = kron.WriterSink.init(&output.interface);
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{
        .submission = .asynchronous,
        .memory_queue = .{ .capacity = 256, .max_record_bytes = 8192 },
        .routes = &.{.{ .name = "console", .sink = console.sink(), .format = .text }},
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer runtime.destroy();
    _ = try runtime.scoped("worker").tryEmit(.info, "ordinary async memory queue", .{ .answer = @as(u32, 42), .password = "private" });
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
}
