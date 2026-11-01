//! Output defaults with route-specific format, sampling, redaction and limits.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .mode = .asynchronous,
        .defaults = .{
            .format = .json,
            .timestamp = .{ .zone = .local },
            .filter = "info",
            .sampling = .{ .every = 2 },
            .redaction = &.{.{ .key = "password", .action = .mask }},
            .max_encoded_record_bytes = 4096,
        },
        // Capture-wide protection removes this value before the shared queue;
        // output policies cannot restore it, even with an empty rule list.
        .capture = .{ .redaction = &.{.{ .key = "access_token", .action = .mask }} },
        .output = .{ .multiple = &.{
            .{
                .name = "file",
                .target = .{ .file = .{ .path = "kron-route-policies.jsonl", .backend = .portable } },
                .sampling = .none,
                .redaction = &.{.{ .key = "password", .action = .drop }},
            },
            .{ .name = "stdout", .target = .stdout, .format = .text, .max_encoded_record_bytes = 2048 },
        } },
    });
    defer logging.destroy();
    const log = logging.scoped("http");
    for (0..4) |request| {
        _ = try log.tryLogfAt(@src(), .info, "request {d} completed", .{@as(u32, @intCast(request))}, .{
            .request = @as(u32, @intCast(request)),
            .password = "example-password",
            .access_token = "example-token",
        });
    }
    try logging.shutdown();
}
