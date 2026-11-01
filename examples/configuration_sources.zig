const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    var bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const route = kron.RouteOptions{ .name = "local", .sink = memory.sink(), .format = .json };
    const runtime = try kron.Runtime.create(init.gpa, init.io, .{ .routes = &.{route} });
    defer runtime.destroy();
    const json =
        \\{
        \\  "filter": "off,worker=debug",
        \\  "redaction": [{"key": "password", "action": "mask"}],
        \\  "predicate": "status >= 500",
        \\  "sampling": {"kind": "every", "every": 2},
        \\  "sample_bypass": "warn"
        \\}
    ;
    var document = try kron.configuration_document.Document.parse(init.gpa, json);
    defer document.deinit();
    const version = try runtime.replaceConfigurationSources(&.{route}, .{
        .file = document.override(),
        .environment = kron.configuration_sources.fromMap(init.environ_map),
        .explicit = .{ .sampling = .none },
    });
    const log = runtime.scoped("worker");
    _ = try log.tryEmit(.warn, "configuration applied", .{ .configuration_version = version.generation, .status = @as(u16, 503), .password = "private" });
    // A later explicit filter-only transaction retains predicate/redaction.
    try runtime.reloadFilter("off,worker=trace");
    _ = try log.tryEmit(.debug, "diagnostic enabled", .{ .status = @as(u16, 500), .password = "private" });
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    var output_buffer: [1024]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output.interface.writeAll(memory.written());
    try output.interface.flush();
}
