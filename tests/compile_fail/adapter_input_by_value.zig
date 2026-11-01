const kron = @import("kron");

pub fn main() void {
    const Input = struct { id: u32 };
    const input: Input = .{ .id = 1 };
    var fields: [1]kron.Field = undefined;
    _ = kron.object(&.{"id"}, input, &fields) catch {};
}
