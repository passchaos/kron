const kron = @import("kron");

pub fn main() void {
    var value: u32 = 42;
    _ = kron.fields.fromAny(&value);
}
