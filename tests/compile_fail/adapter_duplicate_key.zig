const kron = @import("kron");

pub fn main() void {
    const Input = struct { id: u32, name: []const u8 };
    _ = kron.MappedAdapter(Input, &.{
        .{ .member = "id", .key = "duplicate" },
        .{ .member = "name", .key = "duplicate" },
    }).init();
}
