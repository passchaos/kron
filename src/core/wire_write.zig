//! Internal value wire implementation shared by validated payload codecs.
//! This module is not exported by kron or codec. Callers finish whole-event
//! validation and capacity checks before writing; public standalone writing
//! remains a validating codec API.
const std = @import("std");
const field = @import("field.zig");

pub const ValueTag = enum(u8) { null_value = 0, boolean = 1, signed = 2, unsigned = 3, float = 4, string = 5, bytes = 6, duration_ns = 7, timestamp_ns = 8, array = 9, group = 10 };

pub fn valueTag(value: field.Value) ValueTag {
    return switch (value) {
        .null_value => .null_value,
        .boolean => .boolean,
        .signed => .signed,
        .unsigned => .unsigned,
        .float => .float,
        .string => .string,
        .bytes => .bytes,
        .duration_ns => .duration_ns,
        .timestamp_ns => .timestamp_ns,
        .array => .array,
        .group => .group,
    };
}

const Tag = ValueTag;

pub const StreamOutput = struct {
    pub const Error = std.Io.Writer.Error;
    writer: *std.Io.Writer,

    pub fn put(self: *StreamOutput, bytes: []const u8) Error!void {
        try self.writer.writeAll(bytes);
    }

    pub fn int(self: *StreamOutput, comptime T: type, value: T) Error!void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        try self.put(&bytes);
    }
};

/// Concrete fixed-buffer output for measured payloads. Avoids the dynamic
/// `std.Io.Writer` vtable and its out-of-line small copies on the hot encode
/// path; the caller already validated the exact total size.
pub const FixedOutput = struct {
    pub const Error = error{BufferTooSmall};
    buffer: []u8,
    index: usize = 0,

    pub fn put(self: *FixedOutput, bytes: []const u8) Error!void {
        if (self.index + bytes.len > self.buffer.len) return error.BufferTooSmall;
        @memcpy(self.buffer[self.index..][0..bytes.len], bytes);
        self.index += bytes.len;
    }

    pub fn int(self: *FixedOutput, comptime T: type, value: T) Error!void {
        const width = @sizeOf(T);
        if (self.index + width > self.buffer.len) return error.BufferTooSmall;
        std.mem.writeInt(T, self.buffer[self.index..][0..width], value, .little);
        self.index += width;
    }
};

pub fn writeBlob(output: anytype, bytes: []const u8) @TypeOf(output.*).Error!void {
    try output.int(u32, @intCast(bytes.len));
    try output.put(bytes);
}

pub fn writeTerminated(output: anytype, bytes: []const u8) @TypeOf(output.*).Error!void {
    try writeBlob(output, bytes);
    try output.int(u8, 0);
}

pub fn writeField(output: anytype, entry: field.Field) @TypeOf(output.*).Error!void {
    try writeBlob(output, entry.key);
    try writeValueTo(output, entry.value);
}

pub fn writeValueTo(output: anytype, value: field.Value) @TypeOf(output.*).Error!void {
    switch (value) {
        .null_value => try output.int(u8, @intFromEnum(Tag.null_value)),
        .boolean => |v| {
            try output.int(u8, @intFromEnum(Tag.boolean));
            try output.int(u8, @intFromBool(v));
        },
        .signed => |v| {
            try output.int(u8, @intFromEnum(Tag.signed));
            try output.int(i128, v);
        },
        .unsigned => |v| {
            try output.int(u8, @intFromEnum(Tag.unsigned));
            try output.int(u128, v);
        },
        .float => |v| {
            try output.int(u8, @intFromEnum(Tag.float));
            try output.int(u64, @bitCast(v));
        },
        .string => |v| {
            try output.int(u8, @intFromEnum(Tag.string));
            try writeBlob(output, v);
        },
        .bytes => |v| {
            try output.int(u8, @intFromEnum(Tag.bytes));
            try writeBlob(output, v);
        },
        .duration_ns => |v| {
            try output.int(u8, @intFromEnum(Tag.duration_ns));
            try output.int(i64, v);
        },
        .timestamp_ns => |v| {
            try output.int(u8, @intFromEnum(Tag.timestamp_ns));
            try output.int(i64, v);
        },
        .array => |values| {
            try output.int(u8, @intFromEnum(Tag.array));
            try output.int(u32, @intCast(values.len));
            for (values) |child| try writeValueTo(output, child);
        },
        .group => |entries| {
            try output.int(u8, @intFromEnum(Tag.group));
            try output.int(u32, @intCast(entries.len));
            for (entries) |entry| try writeField(output, entry);
        },
    }
}
