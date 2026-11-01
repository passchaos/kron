//! Explicit typed configuration sources. Merge borrows data without parsing,
//! reading process globals, or allocating; the runtime validates and owns the
//! resulting complete configuration when it publishes a transaction.
const std = @import("std");
const environment = @import("env.zig");
const sampler = @import("../pipeline/sampler.zig");

pub const Level = @import("../core/level.zig").Level;
pub const Rule = @import("../pipeline/redact.zig").Rule;
pub const RoutePolicy = @import("../core/runtime_types.zig").RoutePolicy;
pub const Entry = environment.Entry;

/// All slices borrow the supplied source storage until runtime installation
/// has copied it. Empty values are explicit values, not missing overrides.
pub const Config = struct {
    filter_spec: []const u8 = "info",
    redaction: []const Rule = &.{},
    sampling: sampler.Config = .none,
    sample_bypass: Level = .warn,
    predicate: ?[]const u8 = null,

    /// A complete transaction, including a non-null default filter. This
    /// prevents the runtime from unintentionally inheriting its previous filter
    /// when the merged sources select library/application defaults.
    pub fn policy(self: Config) RoutePolicy {
        return .{
            .default_filter = self.filter_spec,
            .redaction = self.redaction,
            .sampling = self.sampling,
            .sample_bypass = self.sample_bypass,
            .predicate = self.predicate,
        };
    }
};

pub const PredicateOverride = union(enum) {
    inherit,
    clear,
    expression: []const u8,
};

pub const Override = struct {
    filter_spec: ?[]const u8 = null,
    redaction: ?[]const Rule = null,
    sampling: ?sampler.Config = null,
    sample_bypass: ?Level = null,
    predicate: PredicateOverride = .inherit,
};

pub const Sources = struct {
    defaults: Config = .{},
    file: Override = .{},
    environment: Override = .{},
    explicit: Override = .{},
};

/// The environment contract covers KRON_LOG only. Other policy fields must
/// come from typed application sources, never invented environment variables.
pub fn fromEntries(entries: []const Entry) Override {
    return .{ .filter_spec = environment.fromEntries(entries).filter_spec };
}

pub fn fromMap(map: *const std.process.Environ.Map) Override {
    return .{ .filter_spec = environment.fromMap(map).filter_spec };
}

/// Per-field precedence: defaults < application file < supplied environment
/// < explicit application override. Inherit preserves the preceding source;
/// clear removes a predicate even when a preceding source supplied one.
pub fn merge(sources: Sources) Config {
    var result = sources.defaults;
    for ([_]Override{ sources.file, sources.environment, sources.explicit }) |override| {
        if (override.filter_spec) |spec| result.filter_spec = spec;
        if (override.redaction) |rules| result.redaction = rules;
        if (override.sampling) |sampling| result.sampling = sampling;
        if (override.sample_bypass) |level| result.sample_bypass = level;
        switch (override.predicate) {
            .inherit => {},
            .clear => result.predicate = null,
            .expression => |expression| result.predicate = expression,
        }
    }
    return result;
}

test "configuration sources apply precedence independently to every policy field" {
    const default_rules = [_]Rule{.{ .key = "default", .action = .drop }};
    const file_rules = [_]Rule{.{ .key = "password", .action = .mask }};
    const explicit_rules = [_]Rule{.{ .key = "token", .action = .drop }};
    var sources: Sources = .{
        .defaults = .{
            .filter_spec = "warn",
            .redaction = &default_rules,
            .sampling = .{ .count = 10 },
            .sample_bypass = .fatal,
            .predicate = "exists(default)",
        },
        .file = .{
            .filter_spec = "info",
            .redaction = &file_rules,
            .sampling = .{ .every = 7 },
            .sample_bypass = .err,
            .predicate = .{ .expression = "exists(file)" },
        },
        .environment = fromEntries(&.{.{ .key = "KRON_LOG", .value = "debug,http=trace" }}),
        .explicit = .{ .sampling = .{ .count = 2 }, .sample_bypass = .trace },
    };
    const config = merge(sources);
    try std.testing.expectEqualStrings("debug,http=trace", config.filter_spec);
    try std.testing.expect(config.redaction.ptr == file_rules[0..].ptr);
    try std.testing.expectEqualDeep(sampler.Config{ .count = 2 }, config.sampling);
    try std.testing.expectEqual(Level.trace, config.sample_bypass);
    try std.testing.expectEqualStrings("exists(file)", config.predicate.?);
    sources.explicit.filter_spec = "off";
    sources.explicit.redaction = &explicit_rules;
    sources.explicit.predicate = .{ .expression = "exists(explicit)" };
    const policy = merge(sources).policy();
    try std.testing.expectEqualStrings("off", policy.default_filter.?);
    try std.testing.expect(policy.redaction.ptr == explicit_rules[0..].ptr);
    try std.testing.expectEqualDeep(sampler.Config{ .count = 2 }, policy.sampling);
    try std.testing.expectEqualStrings("exists(explicit)", policy.predicate.?);
}

test "configuration sources preserve explicit empty values and complete defaults" {
    const config = merge(.{
        .file = .{
            .filter_spec = "fatal",
            .redaction = &.{.{ .key = "password", .action = .mask }},
            .sampling = .{ .count = 10 },
            .predicate = .{ .expression = "exists(password)" },
        },
        .explicit = .{
            .filter_spec = "",
            .redaction = &.{},
            .sampling = .none,
            .sample_bypass = .off,
            .predicate = .{ .expression = "" },
        },
    });
    const policy = config.policy();
    try std.testing.expectEqualStrings("", policy.default_filter.?);
    try std.testing.expectEqual(@as(usize, 0), policy.redaction.len);
    try std.testing.expectEqualDeep(sampler.Config.none, policy.sampling);
    try std.testing.expectEqual(Level.off, policy.sample_bypass);
    try std.testing.expectEqualStrings("", policy.predicate.?);
    const defaults = merge(.{}).policy();
    try std.testing.expectEqualStrings("info", defaults.default_filter.?);
    try std.testing.expectEqual(Level.warn, defaults.sample_bypass);
    try std.testing.expect(defaults.predicate == null);
    try std.testing.expectEqualDeep(sampler.Config.none, defaults.sampling);
}

test "configuration sources predicate inherit clear and expression retain three states" {
    var sources: Sources = .{
        .defaults = .{ .predicate = "exists(base)" },
        .file = .{ .predicate = .clear },
    };
    try std.testing.expect(merge(sources).predicate == null);
    sources.explicit.predicate = .{ .expression = "exists(explicit)" };
    try std.testing.expectEqualStrings("exists(explicit)", merge(sources).predicate.?);
    sources.explicit.predicate = .inherit;
    try std.testing.expect(merge(sources).predicate == null);
    sources.file.predicate = .{ .expression = "exists(file)" };
    sources.environment.predicate = .clear;
    try std.testing.expect(merge(sources).policy().predicate == null);
    sources.explicit.predicate = .{ .expression = "invalid expression is not parsed here (" };
    try std.testing.expectEqualStrings("invalid expression is not parsed here (", merge(sources).predicate.?);
}

test "configuration sources borrow input storage and can merge entirely at comptime" {
    var filter_spec = "info,http=trace".*;
    var predicate = "exists(status)".*;
    var key = "password".*;
    var rules = [_]Rule{.{ .key = &key, .action = .mask }};
    const config = merge(.{
        .environment = fromEntries(&.{.{ .key = "KRON_LOG", .value = &filter_spec }}),
        .explicit = .{ .redaction = &rules, .predicate = .{ .expression = &predicate } },
    });
    const policy = config.policy();
    try std.testing.expect(config.filter_spec.ptr == filter_spec[0..].ptr);
    try std.testing.expect(config.redaction.ptr == rules[0..].ptr);
    try std.testing.expect(config.redaction[0].key.ptr == key[0..].ptr);
    try std.testing.expect(policy.predicate.?.ptr == predicate[0..].ptr);
    const static_policy = comptime merge(.{
        .environment = fromEntries(&.{.{ .key = "KRON_LOG", .value = "trace" }}),
        .explicit = .{ .sampling = .{ .every = 3 }, .predicate = .clear },
    }).policy();
    try std.testing.expectEqualStrings("trace", static_policy.default_filter.?);
    try std.testing.expectEqualDeep(sampler.Config{ .every = 3 }, static_policy.sampling);
    try std.testing.expect(static_policy.predicate == null);
}

test "configuration sources supplied environment map reads only KRON_LOG without allocation" {
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var map = std.process.Environ.Map.init(allocator.allocator());
    defer map.deinit();
    try map.put("KRON_LOG", "db=trace");
    try map.put("KRON_SAMPLING", "count=0");
    try map.put("KRON_REDACTION", "password=drop");
    try map.put("KRON_PREDICATE", "exists(secret)");
    const allocations = allocator.allocations;
    allocator.fail_index = allocator.alloc_index;
    const override = fromMap(&map);
    const config = merge(.{ .environment = override });
    try std.testing.expectEqualStrings("db=trace", config.policy().default_filter.?);
    try std.testing.expect(override.redaction == null);
    try std.testing.expect(override.sampling == null);
    try std.testing.expect(override.sample_bypass == null);
    try std.testing.expect(override.predicate == .inherit);
    try std.testing.expect(config.filter_spec.ptr == map.get("KRON_LOG").?.ptr);
    const entries = fromEntries(&.{
        .{ .key = "KRON_LOG", .value = "warn" },
        .{ .key = "KRON_SAMPLING", .value = "count=0" },
        .{ .key = "KRON_LOG", .value = "" },
    });
    try std.testing.expectEqualStrings("", entries.filter_spec.?);
    try std.testing.expect(entries.sampling == null);
    try std.testing.expectEqual(allocations, allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
}
