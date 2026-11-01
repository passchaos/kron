const kron = @import("kron");

pub fn main() void {
    const value = [_]u8{ 'a', 'b', 'c' };
    _ = kron.fields.fromAny(value);
}
