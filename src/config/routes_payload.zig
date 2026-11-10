//! Cold route-policy payload construction and comparison helpers.
const std = @import("std");
const types = @import("../core/runtime_types.zig");
const Level = @import("../core/level.zig").Level;
const Filter = @import("filter.zig").Filter;
const redact = @import("../pipeline/redact.zig");
const sampling = @import("../pipeline/sampler.zig");
const Predicate = @import("../pipeline/predicate.zig").Predicate;
const output_policy = @import("output_policy.zig");
const time = @import("../time/root.zig");

const Route = types.Route;
const RouteOptions = types.RouteOptions;
const Policy = types.RoutePolicy;
const max_routes = types.max_routes;

pub const Payload = struct {
    routes: []Route,
    fingerprint: u64,
    redactor: redact.Redactor,
    sampler: sampling.Sampler,
    sample_bypass: Level,
    sampling_overrides: u64 = 0,
    default_filter: ?Filter,
    filter_generation: u64 = 1,
    predicate: ?Predicate,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: []const RouteOptions, policy: Policy, require_identity: bool, budget: usize) !Payload {
        if (options.len == 0 or options.len > max_routes) return error.InvalidOptions;
        const redactor = try redact.Redactor.init(policy.redaction);
        const sampler = try sampling.Sampler.init(policy.sampling);
        const default_filter = if (policy.default_filter) |spec| try Filter.parse(spec) else null;
        const predicate = if (policy.predicate) |spec| try Predicate.parse(spec) else null;
        var bytes = std.math.mul(usize, options.len, @sizeOf(Route)) catch return error.ConfigBudgetExceeded;
        for (options, 0..) |option, index| {
            if (option.name.len == 0) return error.InvalidRouteName;
            for (options[0..index]) |previous| {
                if (std.mem.eql(u8, option.name, previous.name)) return error.DuplicateRoute;
            }
            const identity = option.recovery_identity orelse option.sink.recovery_identity;
            if (require_identity and option.delivery == .required and (identity == null or identity.?.len == 0))
                return error.RecoveryIdentityRequired;
            if (option.reclaim_after == .durable and !option.sink.supports_durable)
                return error.UnsupportedDurability;
            if (option.timestamp) |timestamp| {
                if (option.format == .binary) return error.InvalidTimestampFormat;
                try timestamp.validate();
                bytes = std.math.add(usize, bytes, @sizeOf(time.Formatter)) catch return error.ConfigBudgetExceeded;
            }
            bytes = std.math.add(usize, bytes, option.name.len) catch return error.ConfigBudgetExceeded;
            if (identity) |binding| bytes = std.math.add(usize, bytes, binding.len) catch return error.ConfigBudgetExceeded;
            if (bytes > budget) return error.ConfigBudgetExceeded;
            if (option.filter) |spec| _ = try Filter.parse(spec);
            if (option.predicate) |spec| _ = try Predicate.parse(spec);
            const policy_options: output_policy.Options = .{ .redaction = option.redaction, .sampling = option.sampling, .sample_bypass = option.sample_bypass, .max_encoded_record_bytes = option.max_encoded_record_bytes };
            try output_policy.Policy.validate(policy_options);
            bytes = std.math.add(usize, bytes, output_policy.Policy.ownedBytes(policy_options)) catch return error.ConfigBudgetExceeded;
            if (bytes > budget) return error.ConfigBudgetExceeded;
        }
        const routes = try allocator.alloc(Route, options.len);
        var initialized: usize = 0;
        errdefer {
            for (routes[0..initialized]) |route| {
                allocator.free(route.name);
                if (route.recovery_identity) |identity| allocator.free(identity);
                if (route.timestamp) |timestamp| allocator.destroy(timestamp);
                if (route.policy) |local| local.destroy(allocator);
            }
            allocator.free(routes);
        }
        var sampling_overrides: u64 = 0;
        for (options, routes, 0..) |option, *route, index| {
            const filter = if (option.filter) |spec| try Filter.parse(spec) else null;
            const route_predicate = if (option.predicate) |spec| try Predicate.parse(spec) else null;
            const name = try allocator.dupe(u8, option.name);
            errdefer allocator.free(name);
            const identity = if (option.recovery_identity orelse option.sink.recovery_identity) |binding|
                try allocator.dupe(u8, binding)
            else
                null;
            errdefer if (identity) |binding| allocator.free(binding);
            const timestamp = if (option.timestamp) |format_options| blk: {
                const cache = try allocator.create(time.Formatter);
                errdefer allocator.destroy(cache);
                cache.* = try time.Formatter.initWithIo(io, format_options);
                break :blk cache;
            } else null;
            errdefer if (timestamp) |cache| allocator.destroy(cache);
            const local_policy = try output_policy.Policy.create(allocator, .{ .redaction = option.redaction, .sampling = option.sampling, .sample_bypass = option.sample_bypass, .max_encoded_record_bytes = option.max_encoded_record_bytes });
            if (option.sampling != null) sampling_overrides |= @as(u64, 1) << @intCast(index);
            var sink = option.sink;
            sink.recovery_identity = identity;
            route.* = .{
                .name = name,
                .sink = sink,
                .format = option.format,
                .timestamp = timestamp,
                .filter = filter,
                .min_level = option.min_level,
                .delivery = option.delivery,
                .reclaim_after = option.reclaim_after,
                .recovery_identity = identity,
                .release = option.release,
                .predicate = route_predicate,
                .policy = local_policy,
            };
            initialized += 1;
        }
        return .{
            .routes = routes,
            .fingerprint = fingerprint(routes),
            .redactor = redactor,
            .sampler = sampler,
            .sample_bypass = policy.sample_bypass,
            .sampling_overrides = sampling_overrides,
            .default_filter = default_filter,
            .predicate = predicate,
        };
    }

    pub fn deinit(self: Payload, allocator: std.mem.Allocator) void {
        freeRoutes(allocator, self.routes);
    }
};

pub fn freeRoutes(allocator: std.mem.Allocator, routes: []Route) void {
    for (routes) |route| {
        allocator.free(route.name);
        if (route.recovery_identity) |identity| allocator.free(identity);
        if (route.timestamp) |timestamp| allocator.destroy(timestamp);
        if (route.policy) |local| local.destroy(allocator);
    }
    allocator.free(routes);
}

/// Keep the original runtime's recovery hash: producer policy and the
/// generation are deliberately independent of target metadata.
pub fn fingerprint(routes: []const Route) u64 {
    var hash = std.hash.Wyhash.init(0x6b726f6e2d726f75);
    for (routes) |route| {
        var size: [8]u8 = undefined;
        std.mem.writeInt(u64, &size, route.name.len, .little);
        hash.update(&size);
        hash.update(route.name);
        hash.update(&.{ @intFromEnum(route.format), @intFromEnum(route.delivery), @intFromEnum(route.reclaim_after) });
        const identity = route.recovery_identity orelse "";
        std.mem.writeInt(u64, &size, identity.len, .little);
        hash.update(&size);
        hash.update(identity);
        // Legacy/default routes keep their exact recovery fingerprint. Opt-in
        // time output has a distinct extension, including offset and precision.
        if (route.timestamp) |timestamp| {
            hash.update("\x00KRONTIME1");
            var offset: [2]u8 = undefined;
            std.mem.writeInt(i16, &offset, timestamp.options.offset.minutes, .little);
            hash.update(&offset);
            hash.update(&.{@intFromEnum(timestamp.options.precision)});
            if (timestamp.options.zone == .local) {
                hash.update("\x00KRONLOCAL1");
                if (timestamp.local_identity) |local_identity| hash.update(&local_identity) else hash.update("unbound");
            }
        }
        if (route.policy) |policy| policy.hashOutput(&hash);
    }
    return hash.final();
}

pub fn sameOwner(a: types.SinkRelease, b: types.SinkRelease) bool {
    return a.context == b.context and a.release == b.release;
}

pub fn routesEqual(a: []const Route, b: []const Route) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (!std.mem.eql(u8, left.name, right.name) or left.format != right.format or
            left.min_level != right.min_level or left.delivery != right.delivery or
            left.reclaim_after != right.reclaim_after or left.sink.context != right.sink.context or
            left.sink.vtable != right.sink.vtable or left.sink.supports_durable != right.sink.supports_durable)
            return false;
        if (!optionalBytesEqual(left.recovery_identity, right.recovery_identity)) return false;
        if (!sameTimestamp(left.timestamp, right.timestamp)) return false;
        if ((left.policy == null) != (right.policy == null)) return false;
        if (left.policy) |policy| if (!policy.eql(right.policy.?)) return false;
        if ((left.release == null) != (right.release == null)) return false;
        if (left.release) |owner| if (!sameOwner(owner, right.release.?)) return false;
        if ((left.filter == null) != (right.filter == null)) return false;
        if ((left.predicate == null) != (right.predicate == null)) return false;
        if (left.predicate) |predicate| {
            const other = right.predicate.?;
            if (!predicate.eql(&other)) return false;
        }
        if (left.filter) |filter| {
            const other = right.filter.?;
            if (filter.default_level != other.default_level or filter.rule_count != other.rule_count or
                filter.scope_bytes_used != other.scope_bytes_used or
                !std.mem.eql(u8, filter.scope_bytes[0..filter.scope_bytes_used], other.scope_bytes[0..other.scope_bytes_used]))
                return false;
            for (filter.rules[0..filter.rule_count], other.rules[0..other.rule_count]) |rule, other_rule| {
                if (!std.meta.eql(rule, other_rule)) return false;
            }
        }
    }
    return true;
}

fn sameTimestamp(left: ?*time.Formatter, right: ?*time.Formatter) bool {
    if (left) |cache| return if (right) |other| cache.eql(other) else false;
    return right == null;
}

fn optionalBytesEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |bytes| return if (b) |other| std.mem.eql(u8, bytes, other) else false;
    return b == null;
}
