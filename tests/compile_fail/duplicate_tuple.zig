const kron = @import("kron");

// Both keys are known at comptime. Dynamic Field slices instead return the
// same DuplicateKey error from their fallible capture call at runtime.
comptime {
    var storage: [2]kron.Field = undefined;
    var count: usize = 0;
    kron.fields.appendFields(&storage, &count, .{
        kron.fields.kv("duplicate", 1),
        kron.fields.kv("duplicate", 2),
    }) catch |failure| @compileError("kron fields: " ++ @errorName(failure));
}

pub fn main() void {}
