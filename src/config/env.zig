const std = @import("std");

pub const Entry = struct {
    key: []const u8,
    value: []const u8,
};

/// Values are borrowed from the explicit sources supplied by the application.
/// DynamicFilter.create/reload copy the selected rule specification.
pub const Config = struct {
    filter_spec: []const u8 = "info",
};

pub const Override = struct {
    filter_spec: ?[]const u8 = null,
};

pub const Sources = struct {
    defaults: Config = .{},
    file: Override = .{},
    environment: Override = .{},
    explicit: Override = .{},
};

/// No implicit process environment reads and no retained global environment.
pub fn fromEntries(entries: []const Entry) Override {
    var result: Override = .{};
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, "KRON_LOG")) result.filter_spec = entry.value;
    }
    return result;
}

pub fn fromMap(map: *const std.process.Environ.Map) Override {
    return .{ .filter_spec = map.get("KRON_LOG") };
}

/// Library defaults < application file < supplied environment < explicit API.
pub fn merge(sources: Sources) Config {
    var result = sources.defaults;
    for ([_]Override{ sources.file, sources.environment, sources.explicit }) |override| {
        if (override.filter_spec) |spec| result.filter_spec = spec;
    }
    return result;
}

test "explicit environment and documented merge precedence" {
    const environment = fromEntries(&.{
        .{ .key = "OTHER", .value = "off" },
        .{ .key = "KRON_LOG", .value = "debug" },
        .{ .key = "KRON_LOG", .value = "trace,http=off" },
    });
    const sources: Sources = .{
        .defaults = .{ .filter_spec = "warn" },
        .file = .{ .filter_spec = "info" },
        .environment = environment,
        .explicit = .{ .filter_spec = "fatal" },
    };
    try std.testing.expectEqualStrings("fatal", merge(sources).filter_spec);
    var without_explicit = sources;
    without_explicit.explicit = .{};
    try std.testing.expectEqualStrings("trace,http=off", merge(without_explicit).filter_spec);
    without_explicit.environment = fromEntries(&.{});
    try std.testing.expectEqualStrings("info", merge(without_explicit).filter_spec);
    try std.testing.expectEqualStrings("info", merge(.{}).filter_spec);
}

test "environment map is supplied by the application" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("KRON_LOG", "db=trace");
    try std.testing.expectEqualStrings("db=trace", fromMap(&map).filter_spec.?);
}
