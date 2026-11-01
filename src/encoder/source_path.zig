//! Unquoted terminal source paths, preserving printable path bytes and UTF-8.
const std = @import("std");
const escaping = @import("escaping.zig");

/// Preserve slashes/backslashes and spaces for terminal link detection; make
/// controls and malformed UTF-8 visible so a source path cannot inject lines.
pub fn write(writer: *std.Io.Writer, path: []const u8) std.Io.Writer.Error!void {
    var index: usize = 0;
    while (index < path.len) {
        const start = index;
        while (index < path.len and path[index] >= 0x20 and path[index] < 0x7f) : (index += 1) {}
        try writer.writeAll(path[start..index]);
        if (index == path.len) return;
        const byte = path[index];
        if (byte >= 0x80) {
            const length = std.unicode.utf8ByteSequenceLength(byte) catch 0;
            if (length != 0 and length <= path.len - index) {
                const sequence = path[index..][0..length];
                if (std.unicode.utf8ValidateSlice(sequence)) {
                    if (length == 3 and sequence[0] == 0xe2 and sequence[1] == 0x80 and (sequence[2] == 0xa8 or sequence[2] == 0xa9)) {
                        try writer.writeAll(if (sequence[2] == 0xa8) "\\u2028" else "\\u2029");
                    } else try writer.writeAll(sequence);
                    index += length;
                    continue;
                }
            }
        }
        switch (byte) {
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                try writer.writeAll("\\x");
                try escaping.hexByte(writer, byte);
            },
        }
        index += 1;
    }
}

test "terminal source paths keep printable bytes without quote delimiters and escape record separators" {
    const cases = .{
        .{ "examples/mmap.zig", "examples/mmap.zig" },
        .{ "src/my file.zig", "src/my file.zig" },
        .{ "src/目录/文件.zig", "src/目录/文件.zig" },
        .{ "src\\worker.zig", "src\\worker.zig" },
        .{ "src/\"name\".zig", "src/\"name\".zig" },
        .{ "src/\n\r\t\x00\x7f\xff.zig", "src/\\n\\r\\t\\x00\\x7f\\xff.zig" },
        .{ "src/\xe2\x80\xa8.zig", "src/\\u2028.zig" },
    };
    inline for (cases) |case| {
        var bytes: [128]u8 = undefined;
        var output = std.Io.Writer.fixed(&bytes);
        try write(&output, case[0]);
        try std.testing.expectEqualStrings(case[1], output.buffered());
        for (0..case[1].len) |capacity| {
            var short = std.Io.Writer.fixed(bytes[0..capacity]);
            try std.testing.expectError(error.WriteFailed, write(&short, case[0]));
        }
    }
}
