const std = @import("std");
const kron = @import("kron");
const Custom = struct {
    pub fn format(_: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("custom");
    }
};

pub fn main() void {
    kron.format.validate("value {f}", @TypeOf(.{Custom{}}));
}
