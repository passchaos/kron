const kron = @import("kron");

pub fn main() void {
    const Input = struct { id: u32 };
    const selected: [65][]const u8 = @splat("id");
    _ = kron.Adapter(Input, &selected).init();
}
