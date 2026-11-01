const std = @import("std");
pub const Level = @import("level.zig").Level;
pub const Field = @import("field.zig").Field;

/// An event borrowed for the duration of submission or encoding. Decode returns
/// this same view, with all slices borrowed from the self-contained payload.
pub const Event = struct {
    level: Level,
    scope: []const u8,
    message: []const u8,
    message_template: bool = false,
    format_args: []const Field = &.{},
    fields: []const Field,
    timestamp_ns: i64,
    session: u64 = 0,
    sequence: u64 = 0,
    channel: u32 = 0,
    route_mask: u64 = 0,
    route_fingerprint: u64 = 0,
    route_generation: u64 = 0,
    config_generation: u64 = 0,
    trace_id: ?[16]u8 = null,
    span_id: ?[8]u8 = null,
    trace_flags: u8 = 0,
    source: ?std.builtin.SourceLocation = null,
    /// Internal provenance hint. Checked decoders set this after validating the
    /// complete wire tree; public encoders ignore it and always validate. Only
    /// the internal delivery path may reuse the decoder's proof.
    tree_validated: bool = false,
};
