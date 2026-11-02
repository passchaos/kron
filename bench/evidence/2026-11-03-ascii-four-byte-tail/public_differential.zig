const std = @import("std");
const before = @import("before");
const after = @import("after");

fn write(comptime Impl: type, writer: *std.Io.Writer, input: []const u8, operation: usize) std.Io.Writer.Error!void {
    switch (operation) {
        0 => try Impl.quoted(writer, input, .json),
        1 => try Impl.quoted(writer, input, .text),
        2 => try Impl.jsonKey(writer, input),
        3 => try Impl.jsonMember(writer, input, false),
        4 => try Impl.jsonMember(writer, input, true),
        else => unreachable,
    }
}

fn compare(input: []const u8) !void {
    var old_storage: [2048]u8 = undefined;
    var new_storage: [2048]u8 = undefined;
    for (0..5) |operation| {
        var complete = std.Io.Writer.fixed(&old_storage);
        try write(before, &complete, input, operation);
        const length = complete.end;
        for (0..length + 2) |capacity| {
            var old_writer = std.Io.Writer.fixed(old_storage[0..capacity]);
            var new_writer = std.Io.Writer.fixed(new_storage[0..capacity]);
            const old_result = write(before, &old_writer, input, operation);
            const new_result = write(after, &new_writer, input, operation);
            if (old_result) |_| {
                try new_result;
            } else |expected| {
                try std.testing.expectError(expected, new_result);
            }
            try std.testing.expectEqual(old_writer.end, new_writer.end);
            try std.testing.expectEqualSlices(u8, old_writer.buffered(), new_writer.buffered());
        }
    }
}

test "frozen public escaping writer bytes and errors match at every destination prefix" {
    const fixed = [_][]const u8{ "", "a", "abc", "abcd", "abcde", "field0", "abcdefg", "abcdefgh", "reference.app", "$bytes:reserved", "雪🙂", "a\"b\\c\t", "\x00\x7f\xff", "abc\xffdef" };
    for (fixed) |input| try compare(input);
    var bytes: [24]u8 = undefined;
    for ([_]usize{ 6, 14, 22 }) |length| {
        const start = length - 5;
        for (0..256) |byte| for (0..4) |lane| {
            @memset(&bytes, 'a');
            bytes[start + lane] = @intCast(byte);
            try compare(bytes[0..length]);
        };
    }
}
