const candidate = @import("candidate.zig");

export fn crc_serial(state: u32, bytes: [*]const u8, length: usize) u32 {
    return candidate.update(.serial, state, bytes[0..length]);
}

export fn crc_parallel(state: u32, bytes: [*]const u8, length: usize) u32 {
    return candidate.update(.parallel, state, bytes[0..length]);
}

export fn crc_tree(state: u32, bytes: [*]const u8, length: usize) u32 {
    return candidate.update(.tree, state, bytes[0..length]);
}
