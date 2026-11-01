const kron = @import("kron");

pub fn main() void {
    const Input = struct { bytes: [4]u8 };
    _ = kron.Adapter(Input, &.{"bytes"}).init();
}
