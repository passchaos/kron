//! Compare public routing decisions with an independent filter scan through
//! synchronous, shared-memory and attached-memory submission and live reloads.
const std = @import("std");
const kron = @import("kron");

const Counter = struct {
    records: usize = 0,
    last_mask: u64 = 0,

    fn sink(self: *Counter) kron.Sink {
        return .{ .context = self, .vtable = &vtable };
    }

    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        const self: *Counter = @ptrCast(@alignCast(context));
        const prefix = "\"route_mask\":";
        const offset = (std.mem.find(u8, record, prefix) orelse return error.MissingRouteMask) + prefix.len;
        const quoted = record[offset] == '"';
        const start = offset + @intFromBool(quoted);
        var end = start;
        while (end < record.len and std.ascii.isDigit(record[end])) : (end += 1) {}
        if (end == start or (quoted and (end == record.len or record[end] != '"'))) return error.InvalidRouteMask;
        self.last_mask = try std.fmt.parseInt(u64, record[start..end], 10);
        self.records += 1;
    }

    fn flush(_: *anyopaque) anyerror!void {}
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = flush };
};

fn expected(routes: []const kron.RouteOptions, configured: []const u8, level: kron.Level, scope: []const u8) !u64 {
    const global = try kron.Filter.parse(configured);
    var mask: u64 = 0;
    for (routes, 0..) |route, index| {
        const threshold = if (route.filter) |spec| (try kron.Filter.parse(spec)).threshold(scope) else global.threshold(scope);
        if (!threshold.allows(level)) continue;
        if (route.min_level) |minimum| if (!minimum.allows(level)) continue;
        mask |= @as(u64, 1) << @intCast(index);
    }
    return mask;
}

fn compare(runtime: *kron.Runtime, log: anytype, routes: []const kron.RouteOptions, counters: []Counter, specification: []const u8, scope: []const u8) !void {
    for (std.enums.values(kron.Level)) |level| {
        const mask = try expected(routes, specification, level, scope);
        const before = runtime.health();
        var counts: [64]usize = undefined;
        for (counters, counts[0..counters.len]) |counter, *count| count.* = counter.records;
        try std.testing.expectEqual(mask != 0, log.enabled(level));
        try std.testing.expectEqual(if (mask != 0) kron.EmitResult.accepted else .filtered, try log.tryEmit(level, "route selection", .{}));
        try runtime.flush(.written);
        const after = runtime.health();
        try std.testing.expectEqual(@as(u64, @intFromBool(mask != 0)), after.accepted - before.accepted);
        try std.testing.expectEqual(after.accepted, after.written);
        for (counters, counts[0..counters.len], 0..) |counter, count, index| {
            const selected = mask & (@as(u64, 1) << @intCast(index)) != 0;
            try std.testing.expectEqual(count + @intFromBool(selected), counter.records);
            if (selected) try std.testing.expectEqual(mask, counter.last_mask);
        }
    }
}

test "public route masks preserve independent filters minimum levels and reloads across all submissions" {
    var counters: [64]Counter = @splat(.{});
    var names: [64][16]u8 = undefined;
    var routes: [64]kron.RouteOptions = undefined;
    const explicit = [_][]const u8{ "off", "trace", "info,db=debug,db.query=off", "warn,db=trace,db.query=err" };
    for (&routes, &names, &counters, 0..) |*route, *name, *counter, index| {
        route.* = .{
            .name = try std.fmt.bufPrint(name, "route-{d}", .{index}),
            .sink = counter.sink(),
            .format = .json,
            .filter = if (index % 3 == 0) explicit[index % explicit.len] else null,
            .min_level = if (index % 4 == 0) @enumFromInt(index % 7) else null,
        };
    }
    // Explicit index 63 exercises the most significant route-mask bit.
    routes[63].filter = "trace";
    inline for (.{ .sync, .asynchronous, .low_latency }) |submission| {
        counters = @splat(.{});
        const runtime = try kron.Runtime.create(std.testing.allocator, std.testing.io, .{
            .submission = submission,
            .memory_queue = if (submission != .sync) .{ .capacity = 8, .max_record_bytes = 1024 } else null,
            .thread_channel_capacity = 8,
            .max_thread_channels = if (submission == .low_latency) 1 else 0,
            .routes = &routes,
            .filter = "off",
            .idle = .sleep,
        });
        defer runtime.destroy();
        const scopes = [_][]const u8{ "db", "db.query", "db.query.child", "database" };
        for (scopes) |scope| {
            const log = if (submission == .low_latency) try runtime.attachThread(.{ .scope = scope }) else runtime.scoped(scope);
            defer if (submission == .low_latency) log.detach() catch {};
            for ([_][]const u8{ "off", "trace", "warn,db=debug,db.query=off" }) |specification| {
                try runtime.reloadFilter(specification);
                try compare(runtime, log, &routes, &counters, specification, scope);
            }
            // Swap inherited/explicit entries and minimum levels. Subsequent
            // attachment/cache refresh must use the new snapshot's masks.
            const old_version = runtime.currentConfiguration();
            for (&routes, 0..) |*route, index| {
                route.filter = if (index % 2 == 0) null else explicit[index % explicit.len];
                route.min_level = if (index % 5 == 0) .fatal else null;
            }
            routes[63].filter = "trace";
            const next = try runtime.replaceConfiguration(&routes, .{ .default_filter = "off,db=info,db.query=warn" });
            try std.testing.expect(next.generation > old_version.generation);
            try compare(runtime, log, &routes, &counters, "off,db=info,db.query=warn", scope);
            _ = try runtime.collectConfigurations();
        }
        try runtime.shutdown(.drain);
    }
}
