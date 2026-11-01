//! Compile-time capabilities; concrete devices can still reject operations.
const builtin = @import("builtin");
const mapping = @import("mapping.zig");

pub const Target = enum { linux, android, windows, macos, ios, unsupported };
pub const target: Target = switch (builtin.os.tag) {
    .linux => if (builtin.abi == .android) .android else .linux,
    .windows => .windows,
    .macos => .macos,
    .ios => .ios,
    else => .unsupported,
};
pub const synchronous = target != .unsupported;
pub const shared_journal = mapping.supported;
pub const memory_queue = synchronous and builtin.cpu.arch.endian() == .little and @sizeOf(usize) == 8;
pub const asynchronous = shared_journal and !builtin.single_threaded;
pub const spsc = asynchronous;
pub const directory_durable_protocol = mapping.durable_supported;
pub const io_uring = builtin.os.tag == .linux;
pub const tsc = builtin.os.tag == .linux and builtin.cpu.arch == .x86_64;
