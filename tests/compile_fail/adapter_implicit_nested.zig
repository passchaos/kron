const kron = @import("kron");

pub fn main() void {
    const Nested = struct { id: u32 };
    const Input = struct { nested: Nested };
    _ = kron.Adapter(Input, &.{"nested"}).init();
}
