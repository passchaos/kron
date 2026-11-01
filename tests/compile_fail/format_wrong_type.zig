const kron = @import("kron");

pub fn main() void {
    kron.format.validate("value {d}", @TypeOf(.{"text"}));
}
