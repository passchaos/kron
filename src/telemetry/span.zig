//! A lightweight span records explicit context and caller-provided monotonic
//! times. Ending it has no logging or exporter side effect.
const std = @import("std");
const trace = @import("trace_context.zig");
pub const TraceContext = trace.TraceContext;
pub const SpanId = trace.SpanId;

pub const Span = struct {
    name: []const u8,
    trace_context: TraceContext,
    parent_span_id: ?SpanId = null,
    started_ns: i64,
    ended_ns: ?i64 = null,

    pub fn start(parent: TraceContext, span_id: SpanId, name: []const u8, started_ns: i64) error{InvalidTraceContext}!Span {
        return .{
            .name = name,
            .trace_context = try parent.child(span_id),
            .parent_span_id = parent.span_id,
            .started_ns = started_ns,
        };
    }

    pub fn root(trace_context: TraceContext, name: []const u8, started_ns: i64) error{InvalidTraceContext}!Span {
        if (!trace_context.isValid()) return error.InvalidTraceContext;
        return .{ .name = name, .trace_context = trace_context, .started_ns = started_ns };
    }

    pub fn context(self: Span) TraceContext {
        return self.trace_context;
    }

    /// First successful end fixes the elapsed time. A repeated end returns
    /// the original duration, so cleanup paths can safely end twice.
    pub fn end(self: *Span, ended_ns: i64) error{InvalidEndTime}!i64 {
        if (self.durationNs()) |duration| return duration;
        const duration = std.math.sub(i64, ended_ns, self.started_ns) catch return error.InvalidEndTime;
        if (duration < 0) return error.InvalidEndTime;
        self.ended_ns = ended_ns;
        return duration;
    }

    pub fn durationNs(self: Span) ?i64 {
        const ended_ns = self.ended_ns orelse return null;
        return std.math.sub(i64, ended_ns, self.started_ns) catch null;
    }
};

test "span propagation and explicit monotonic completion" {
    const parent: TraceContext = .{ .trace_id = .{1} ** 16, .span_id = .{2} ** 8, .flags = 1 };
    var span = try Span.start(parent, .{3} ** 8, "request", 100);
    try std.testing.expectEqualSlices(u8, &parent.span_id, &span.parent_span_id.?);
    try std.testing.expectEqualSlices(u8, &parent.trace_id, &span.context().trace_id);
    try std.testing.expectEqual(@as(?i64, null), span.durationNs());
    try std.testing.expectError(error.InvalidEndTime, span.end(99));
    try std.testing.expectEqual(@as(i64, 25), try span.end(125));
    try std.testing.expectEqual(@as(i64, 25), try span.end(500));
    try std.testing.expectEqual(@as(?i64, 25), span.durationNs());
}
