const std = @import("std");
const Event = @import("../core/event.zig").Event;
const common = @import("common.zig");

pub fn encode(event: Event, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try common.encode(.text, event, writer);
}

test "text golden escapes message, keys and binary data" {
    const field = @import("../core/field.zig");
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(.{ .level = .info, .scope = "worker", .message = "done\n\xff", .fields = &.{ field.kv("a=b", 12), field.kv("blob", field.bytes("\xff")) }, .timestamp_ns = -1 }, &writer);
    try std.testing.expectEqualStrings("-1 info scope=\"worker\" message=\"done\\n\\xff\" session=0 channel=0 sequence=0 \"a=b\"=12 \"blob\"=\"hex:ff\"\n", writer.buffered());
}
