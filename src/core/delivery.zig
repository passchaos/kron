//! Single-owner encoded fanout. Consecutive equal format/time options reuse
//! the encoded event; distinct timestamps keep independent route-owned caches.
//! callbacks only record diagnostics and never invoke user hooks under locks.
const std = @import("std");
const Event = @import("event.zig").Event;
const codec = @import("codec.zig");
const field = @import("field.zig");
const encoder = @import("../encoder/root.zig");
const common = @import("../encoder/common.zig");
const wire_json = @import("../encoder/wire_json.zig");
const types = @import("runtime_types.zig");
const Source = @import("diagnostics.zig").ReportSource;

pub const ErrorRecorder = struct {
    context: *anyopaque,
    record: *const fn (*anyopaque, anyerror, Source) void,

    fn note(self: ErrorRecorder, err: anyerror, source: Source) void {
        self.record(self.context, err, source);
    }
};

pub fn emit(routes: []const types.Route, scratch: []u8, event: Event, diagnostics: ErrorRecorder) !void {
    for (std.enums.values(encoder.Format)) |format| {
        var encoded: ?[]const u8 = null;
        var timestamp: ?*@import("../time/root.zig").Formatter = null;
        var redactor: ?*@import("../pipeline/redact.zig").Redactor = null;
        for (routes, 0..) |*route, index| {
            if (route.format != format or event.route_mask & (@as(u64, 1) << @intCast(index)) == 0) continue;
            const route_redactor = if (route.policy) |policy| policy.redactor else null;
            if (encoded == null or !sameTime(timestamp, route.timestamp) or redactor != route_redactor) {
                encoded = if (route_redactor != null)
                    @import("delivery_redaction.zig").render(route, event, scratch, encodeRecord) catch return error.EncodedRecordTooLarge
                else
                    encodeRecord(route, scratch, event) catch return error.EncodedRecordTooLarge;
                timestamp = route.timestamp;
                redactor = route_redactor;
            }
            if (route.policy) |policy| if (policy.max_encoded_record_bytes) |limit| if (encoded.?.len > limit) {
                diagnostics.note(error.EncodedRecordTooLarge, .write);
                if (route.delivery == .required) return error.EncodedRecordTooLarge;
                continue;
            };
            route.sink.writeRecord(encoded.?) catch |err| {
                diagnostics.note(err, .write);
                if (route.delivery == .required) return err;
            };
        }
    }
}

fn encodeRecord(route: *const types.Route, scratch: []u8, event: Event) ![]const u8 {
    var output = std.Io.Writer.fixed(scratch);
    switch (route.format) {
        .text => try common.encodeDecoded(.text, event, route.timestamp, &output),
        .json => try common.encodeDecoded(.json, event, route.timestamp, &output),
        .logfmt => try common.encodeDecoded(.logfmt, event, route.timestamp, &output),
        .binary => if (route.timestamp) |cache| try encoder.encodeWithTime(.binary, event, cache, &output) else try encoder.encode(.binary, event, &output),
    }
    return output.buffered();
}

fn sameTime(left: ?*@import("../time/root.zig").Formatter, right: ?*@import("../time/root.zig").Formatter) bool {
    if (left) |cache| return if (right) |other| cache.eql(other) else false;
    return right == null;
}

pub fn validateBoundary(routes: []const types.Route, mask: u64, boundary: types.Flush) !void {
    if (boundary == .durable) for (routes, 0..) |*route, index| {
        if (mask & (@as(u64, 1) << @intCast(index)) != 0 and !route.sink.supports_durable) return error.UnsupportedDurability;
    };
}

pub fn flush(routes: []const types.Route, mask: u64, boundary: types.Flush, only_required: bool, diagnostics: ErrorRecorder) !void {
    if (boundary == .durable) for (routes, 0..) |*route, index| {
        if (mask & (@as(u64, 1) << @intCast(index)) == 0 or (only_required and route.delivery != .required)) continue;
        if (!route.sink.supports_durable) return error.UnsupportedDurability;
    };
    for (routes, 0..) |*route, index| {
        if (mask & (@as(u64, 1) << @intCast(index)) == 0 or (only_required and route.delivery != .required)) continue;
        route.sink.flush() catch |err| {
            diagnostics.note(err, .flush);
            if (route.delivery == .required or only_required) return err;
            continue;
        };
        if (boundary == .durable or route.reclaim_after == .durable) {
            if (!route.sink.supports_durable) return error.UnsupportedDurability;
            route.sink.sync() catch |err| {
                diagnostics.note(err, .sync);
                if (route.delivery == .required or only_required) return err;
            };
        }
    }
}

pub fn needsDurableReclaim(routes: []const types.Route, mask: u64) bool {
    for (routes, 0..) |*route, index| {
        if (mask & (@as(u64, 1) << @intCast(index)) != 0 and route.delivery == .required and route.reclaim_after == .durable) return true;
    }
    return false;
}

/// Fused consumer path for one JSON route. Returns false when the payload or
/// route shape is not eligible; the caller then uses the normal decode path.
pub fn emitWireFused(routes: []const types.Route, mask: u64, payload: []const u8, header: codec.EventHeader, definition: ?@import("schema_codec.zig").Definition, preformatted: ?[]const u8, output: []u8, keys: []field.Field, diagnostics: ErrorRecorder) !bool {
    var matched: ?*const types.Route = null;
    var count: usize = 0;
    for (routes, 0..) |*route, index| {
        if (mask & (@as(u64, 1) << @intCast(index)) == 0) continue;
        count += 1;
        matched = route;
    }
    if (count != 1) return false;
    const route = matched.?;
    if (route.policy) |policy| if (policy.redactor != null) return false;
    const format: wire_json.Format = switch (route.format) {
        .json => .json,
        .text => .text,
        .logfmt => .logfmt,
        .binary => return false,
    };
    const bytes = if (preformatted) |bytes| bytes else blk: {
        const rendered = if (definition) |canonical|
            wire_json.renderReference(format, payload, header, canonical, output, keys, route.timestamp)
        else
            wire_json.render(format, payload, header, output, keys, route.timestamp);
        break :blk rendered catch |err| switch (err) {
            error.Fallback => return false,
            error.WriteFailed => {
                // A short output scratch must not hide a later schema/value error.
                // The materialized decoder historically validates before encoding.
                if (definition) |canonical| _ = try @import("schema_codec.zig").resolve(payload, canonical, keys);
                return error.EncodedRecordTooLarge;
            },
            else => return err,
        };
    };
    if (route.policy) |policy| if (policy.max_encoded_record_bytes) |limit| if (bytes.len > limit) {
        diagnostics.note(error.EncodedRecordTooLarge, .write);
        if (route.delivery == .required) return error.EncodedRecordTooLarge;
        return true;
    };
    route.sink.writeRecord(bytes) catch |err| {
        diagnostics.note(err, .write);
        if (route.delivery == .required) return err;
    };
    return true;
}
