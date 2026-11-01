const kron = @import("kron");

pub fn main() void {
    kron.format.validate("value {d} and {s}", @TypeOf(.{@as(u16, 42)}));
}
