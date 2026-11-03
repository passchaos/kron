const std = @import("std");
const journal = @import("journal/journal.zig");
const format = @import("journal/format.zig");

pub fn main(init: std.process.Init) !void {
    try writeV1(init);
    try writeV2(init);
}

fn writeV1(init: std.process.Init) !void {
    const store = try journal.Journal.create(init.gpa, init.io, .{
        .path = "v1-old-binary-aarch64.journal",
        .capacity = 4,
        .max_record_bytes = 64,
        .schema_capacity = 0,
        .max_schema_bytes = 0,
    });
    if (format.get(u32, store.mapping.bytes, 8) != 1) return error.UnexpectedVersion;
    var reservation = try store.reserve();
    errdefer reservation.abort();
    const payload = "old binary aarch64 v1 payload";
    @memcpy(reservation.buffer()[0..payload.len], payload);
    try reservation.commit(payload.len);
    store.deinit();
}

fn writeV2(init: std.process.Init) !void {
    const store = try journal.Journal.create(init.gpa, init.io, .{
        .path = "v2-old-binary-aarch64.journal",
        .capacity = 4,
        .max_record_bytes = 64,
        .schema_capacity = 4,
        .max_schema_bytes = 1024,
    });
    if (format.get(u32, store.mapping.bytes, 8) != 2) return error.UnexpectedVersion;
    const reference = try store.registerSchema(.{ .scope = "old.binary.v2", .message = "old registered event" });
    var schema_reservation = try store.reserveWithSchema(reference);
    errdefer schema_reservation.abort();
    const schema_payload = "old binary aarch64 v2 schema payload";
    @memcpy(schema_reservation.buffer()[0..schema_payload.len], schema_payload);
    try schema_reservation.commit(schema_payload.len);
    var ordinary_reservation = try store.reserve();
    errdefer ordinary_reservation.abort();
    const ordinary_payload = "old binary aarch64 v2 ordinary payload";
    @memcpy(ordinary_reservation.buffer()[0..ordinary_payload.len], ordinary_payload);
    try ordinary_reservation.commit(ordinary_payload.len);
    store.deinit();
}
