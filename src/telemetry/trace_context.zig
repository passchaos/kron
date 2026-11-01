//! Trace context is passed explicitly across tasks; there is no thread-local
//! state and no implicit ID generation or sampling decision.
const std = @import("std");
pub const TraceId = [16]u8;
pub const SpanId = [8]u8;

pub const TraceContext = struct {
    trace_id: TraceId,
    span_id: SpanId,
    flags: u8 = 0,

    pub const sampled_flag: u8 = 1;

    pub fn isValid(self: TraceContext) bool {
        return nonzero(&self.trace_id) and nonzero(&self.span_id);
    }

    pub fn isSampled(self: TraceContext) bool {
        return self.flags & sampled_flag != 0;
    }

    pub fn child(self: TraceContext, span_id: SpanId) error{InvalidTraceContext}!TraceContext {
        if (!self.isValid() or !nonzero(&span_id)) return error.InvalidTraceContext;
        return .{ .trace_id = self.trace_id, .span_id = span_id, .flags = self.flags };
    }
};

fn nonzero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return true;
    return false;
}

test "trace context child retains trace and flags with explicit span ID" {
    const parent: TraceContext = .{ .trace_id = .{1} ** 16, .span_id = .{2} ** 8, .flags = 0x81 };
    const child = try parent.child(.{3} ** 8);
    try std.testing.expectEqualSlices(u8, &parent.trace_id, &child.trace_id);
    try std.testing.expectEqualSlices(u8, &(.{3} ** 8), &child.span_id);
    try std.testing.expect(child.isSampled());
    try std.testing.expectEqual(@as(u8, 0x81), child.flags);
    try std.testing.expectError(error.InvalidTraceContext, parent.child(.{0} ** 8));
}
