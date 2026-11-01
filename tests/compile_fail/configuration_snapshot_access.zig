const kron = @import("kron");

pub fn main() void {
    const runtime: *kron.Runtime = undefined;
    // The public runtime cannot expose a typed mutable Manager/Snapshot path.
    _ = runtime.configuration;
}
