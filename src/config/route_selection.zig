//! Immutable precomputed level and predicate masks. Scope-dependent filters run
//! against the owning snapshot; inherited level filters need no route scan.
const std = @import("std");
const Level = @import("../core/level.zig").Level;
const Route = @import("../core/runtime_types.zig").Route;

pub const Selection = struct {
    inherited: [7]u64 = @splat(0),
    explicit_filters: u64 = 0,
    predicates: u64 = 0,

    pub fn init(routes: []const Route) Selection {
        std.debug.assert(routes.len <= 64);
        var result: Selection = .{};
        for (routes, 0..) |*route, index| {
            const bit = @as(u64, 1) << @intCast(index);
            if (route.predicate != null) result.predicates |= bit;
            if (route.filter != null) {
                result.explicit_filters |= bit;
                continue;
            }
            for (std.enums.values(Level)) |level| {
                if (!Level.trace.allows(level)) continue;
                if (route.min_level) |minimum| if (!minimum.allows(level)) continue;
                result.inherited[@intFromEnum(level)] |= bit;
            }
        }
        return result;
    }

    pub fn mask(self: *const Selection, routes: []const Route, level: Level, scope: []const u8, configured: Level) u64 {
        if (level == .off) return 0;
        var result: u64 = if (configured.allows(level)) self.inherited[@intFromEnum(level)] else 0;
        var remaining = self.explicit_filters;
        while (remaining != 0) {
            const index: u6 = @intCast(@ctz(remaining));
            const bit = @as(u64, 1) << index;
            remaining &= remaining - 1;
            const route = &routes[index];
            if (route.min_level) |minimum| if (!minimum.allows(level)) continue;
            const threshold = route.filter.?.threshold(scope);
            if (threshold.allows(level)) result |= bit;
        }
        return result;
    }
};

test "precomputed route masks equal the route scan for every level scope and 64-bit route index" {
    const Filter = @import("filter.zig").Filter;
    const Predicate = @import("../pipeline/predicate.zig").Predicate;
    const Sink = @import("../sink/interface.zig").Sink;
    const Noop = struct {
        fn write(_: *anyopaque, _: []const u8) anyerror!void {}
        fn flush(_: *anyopaque) anyerror!void {}
        const vtable: Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = flush };
    };
    var context: u8 = 0;
    var routes: [64]Route = undefined;
    var names: [64][1]u8 = undefined;
    const predicate = try Predicate.parse("exists(status)");
    const rules = [_][]const u8{ "off", "trace", "info,db=trace,db.query=off,http=err", "warn,http=debug,http.server=off", "fatal,worker=info" };
    for (&routes, &names, 0..) |*route, *name, index| {
        name.* = .{@intCast(index)};
        route.* = .{
            .name = name,
            .sink = .{ .context = &context, .vtable = &Noop.vtable },
            .format = .json,
            .filter = if (index % 3 == 0) try Filter.parse(rules[index % rules.len]) else null,
            .min_level = if (index % 4 == 0) @enumFromInt(index % 7) else null,
            .delivery = .required,
            .reclaim_after = .written,
            .recovery_identity = null,
            .release = null,
            .predicate = if (index % 5 < 2 or index == 63) predicate else null,
        };
    }
    const scopes = [_][]const u8{ "", "db", "db.query", "db.query.child", "database", "http", "http.server", "http.serverx", "worker", "other" };
    for ([_]usize{ 0, 1, 2, 7, 63, 64 }) |count| {
        const selection = Selection.init(routes[0..count]);
        var expected_predicates: u64 = 0;
        for (routes[0..count], 0..) |*route, index| {
            if (route.predicate != null) expected_predicates |= @as(u64, 1) << @intCast(index);
        }
        try std.testing.expectEqual(expected_predicates, selection.predicates);
        for (std.enums.values(Level)) |configured| for (std.enums.values(Level)) |level| for (scopes) |scope| {
            var expected: u64 = 0;
            var expected_selected_predicates: u64 = 0;
            for (routes[0..count], 0..) |*route, index| {
                const threshold = if (route.filter) |*filter| filter.threshold(scope) else configured;
                if (!threshold.allows(level)) continue;
                if (route.min_level) |minimum| if (!minimum.allows(level)) continue;
                expected |= @as(u64, 1) << @intCast(index);
                if (route.predicate != null) expected_selected_predicates |= @as(u64, 1) << @intCast(index);
            }
            const selected = selection.mask(routes[0..count], level, scope, configured);
            try std.testing.expectEqual(expected, selected);
            try std.testing.expectEqual(expected_selected_predicates, selected & selection.predicates);
        };
    }
    for (&routes) |*route| {
        route.filter = null;
        route.min_level = null;
    }
    const inherited = Selection.init(&routes);
    try std.testing.expectEqual(std.math.maxInt(u64), inherited.mask(&routes, .info, "any", .trace));
    try std.testing.expectEqual(@as(u64, 0), inherited.mask(&routes, .info, "any", .off));
    routes[63].filter = try Filter.parse("trace");
    const override = Selection.init(&routes);
    try std.testing.expectEqual(@as(u64, 1) << 63, override.mask(&routes, .info, "any", .off));

    // Published selections keep their predicate presence until rebuilt, while
    // changing only predicates leaves the precomputed level filters untouched.
    const removed = (@as(u64, 1) << 0) | (@as(u64, 1) << 1) | (@as(u64, 1) << 63);
    try std.testing.expectEqual(removed, override.predicates & removed);
    routes[0].predicate = null;
    routes[1].predicate = null;
    routes[63].predicate = null;
    routes[2].predicate = predicate;
    const rebuilt = Selection.init(&routes);
    try std.testing.expectEqual(removed, override.predicates & removed);
    try std.testing.expectEqual((override.predicates & ~removed) | (@as(u64, 1) << 2), rebuilt.predicates);
    try std.testing.expectEqual(override.inherited, rebuilt.inherited);
    try std.testing.expectEqual(override.explicit_filters, rebuilt.explicit_filters);
    routes[2].predicate = try Predicate.parse("exists(other)");
    const changed_expression = Selection.init(&routes);
    try std.testing.expectEqual(rebuilt.predicates, changed_expression.predicates);
    for (&routes) |*route| route.predicate = null;
    const no_predicates = Selection.init(&routes);
    try std.testing.expectEqual(@as(u64, 0), no_predicates.predicates);
    for (&routes) |*route| route.predicate = predicate;
    const all_predicates = Selection.init(&routes);
    try std.testing.expectEqual(std.math.maxInt(u64), all_predicates.predicates);
}
