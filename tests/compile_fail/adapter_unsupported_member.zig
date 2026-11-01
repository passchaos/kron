const kron = @import("kron");

pub fn main() void {
    const Input = struct { pointer: *const u32 };
    _ = kron.Adapter(Input, &.{"pointer"}).init();
}
