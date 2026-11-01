//! Public enabled() checks with one/many routes. One clock pair per batch;
//! runtime setup and configured filters stay outside the measured region.
const std = @import("std");
const builtin = @import("builtin");
const kron = @import("kron");

const Shape = enum { inherited, mixed, independent };
const iterations = 10000;
const repetitions = 5;
const scopes = [_][]const u8{ "app", "app.db", "app.db.query", "app.dbx", "noisy", "worker", "worker.io", "other" };
const levels = std.enums.values(kron.Level);

const Noop = struct {
    fn write(_: *anyopaque, _: []const u8) anyerror!void {
        return error.UnexpectedOutput;
    }
    fn flush(_: *anyopaque) anyerror!void {}
    const vtable: kron.Sink.VTable = .{ .writeRecord = write, .flush = flush, .sync = flush };
};

pub fn main(init: std.process.Init) !void {
    var routes: [64]kron.RouteOptions = undefined;
    var names: [64][16]u8 = undefined;
    var context: u8 = 0;
    var output_bytes: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_bytes);
    const specifications = [_][]const u8{ "trace", "off", "info,app.db=debug,app.db.query=off,noisy=off", "warn,worker=trace" };
    for ([_]usize{ 1, 8, 64 }) |route_count| for (std.enums.values(Shape)) |shape| {
        var expected: [scopes.len][levels.len]bool = undefined;
        const global = try kron.Filter.parse("info,app.db=trace,noisy=off");
        for (routes[0..route_count], names[0..route_count], 0..) |*route, *name, index| {
            route.* = .{
                .name = try std.fmt.bufPrint(name, "route-{d}", .{index}),
                .sink = .{ .context = &context, .vtable = &Noop.vtable },
                .filter = if (shape == .independent or (shape == .mixed and index % 4 == 0)) specifications[index % specifications.len] else null,
                .min_level = if (index % 3 == 0) .warn else null,
            };
        }
        for (scopes, 0..) |scope, s| for (levels, 0..) |level, l| {
            expected[s][l] = false;
            for (routes[0..route_count]) |route| {
                const threshold = if (route.filter) |spec| (try kron.Filter.parse(spec)).threshold(scope) else global.threshold(scope);
                if (!threshold.allows(level)) continue;
                if (route.min_level) |minimum| if (!minimum.allows(level)) continue;
                expected[s][l] = true;
            }
        };
        var failing = std.testing.FailingAllocator.init(init.gpa, .{});
        const runtime = try kron.Runtime.create(failing.allocator(), init.io, .{ .routes = routes[0..route_count], .filter = "info,app.db=trace,noisy=off" });
        defer runtime.destroy();
        failing.fail_index = failing.alloc_index;
        failing.resize_fail_index = failing.resize_index;
        for (scopes, 0..) |scope, s| for (levels, 0..) |level, l| {
            if (runtime.enabled(level, scope) != expected[s][l]) return error.IncorrectEnabledDecision;
        };
        var expected_checksum: u64 = 0;
        for (0..iterations) |index| expected_checksum += @intFromBool(expected[index % scopes.len][index % levels.len]);
        for (0..repetitions) |repetition| {
            var checksum: u64 = 0;
            const begin = std.Io.Clock.awake.now(init.io);
            for (0..iterations) |index| {
                const enabled = runtime.enabled(levels[index % levels.len], scopes[index % scopes.len]);
                std.mem.doNotOptimizeAway(enabled);
                checksum += @intFromBool(enabled);
            }
            const elapsed = @max(0, begin.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
            if (checksum != expected_checksum or failing.has_induced_failure) return error.IncorrectBatch;
            try std.json.Stringify.value(.{
                .benchmark = "route-enabled",
                .routes = route_count,
                .shape = shape,
                .repetition = repetition,
                .iterations = iterations,
                .elapsed_ns = elapsed,
                .ns_per_call = @as(f64, @floatFromInt(elapsed)) / iterations,
                .checksum = checksum,
                .runtime_allocations_in_batch = 0,
                .clock_pairs = 1,
                .scopes = scopes.len,
                .levels = levels.len,
                .optimize = builtin.mode,
                .zig = builtin.zig_version_string,
                .scope = "public enabled only; no emit, queue or output throughput claim",
            }, .{}, &output.interface);
            try output.interface.writeByte('\n');
        }
    };
    try output.interface.flush();
}
