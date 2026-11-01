const kron = @import("kron");

pub fn main() void {
    const Input = struct { id: u32 };
    _ = kron.Adapter(Input, &.{"missing"}).init();
}
