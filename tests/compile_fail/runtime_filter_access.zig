const kron = @import("kron");
export fn bypass(runtime: *kron.Runtime) void {
    runtime.filter.reload("off") catch {};
}
pub fn main() void {}
