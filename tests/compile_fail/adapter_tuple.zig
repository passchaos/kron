const kron = @import("kron");

pub fn main() void {
    _ = kron.Adapter(@TypeOf(.{ 1, 2 }), &.{"0"}).init();
}
