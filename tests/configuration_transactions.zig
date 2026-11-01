const std = @import("std");
const kron = @import("kron");
const testing = std.testing;

test "source transaction publishes filter redaction predicate and sampling together" {
    var bytes: [16 * 1024]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{.{ .name = "output", .sink = memory.sink() }} });
    defer runtime.destroy();
    var filter_spec = "off,hot=debug".*;
    var key = "password".*;
    var predicate = "status >= 500".*;
    const rules = [_]kron.configuration_sources.Rule{.{ .key = &key, .action = .mask }};
    const version = try runtime.replaceConfigurationSources(&.{.{ .name = "output", .sink = memory.sink() }}, .{
        .defaults = .{ .filter_spec = "off", .sampling = .{ .count = 2 } },
        .file = .{ .filter_spec = "info", .redaction = &rules, .predicate = .{ .expression = &predicate } },
        .environment = kron.configuration_sources.fromEntries(&.{.{ .key = "KRON_LOG", .value = &filter_spec }}),
        .explicit = .{ .sampling = .{ .every = 2 } },
    });
    @memset(&filter_spec, 'x');
    @memset(&key, 'x');
    @memset(&predicate, 'x');
    const log = runtime.scoped("hot");
    try testing.expect(log.enabled(.debug));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.debug, "all policy", .{ .status = @as(u16, 503), .password = "private" }));
    try testing.expectEqual(kron.EmitResult.sampled, try log.tryEmit(.debug, "sampled", .{ .status = @as(u16, 503) }));
    try testing.expectEqual(kron.EmitResult.filtered, try log.tryEmit(.debug, "predicate", .{ .status = @as(u16, 200) }));
    try testing.expectEqual(kron.EmitResult.filtered, try runtime.scoped("other").tryEmit(.fatal, "scope", .{}));
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, std.mem.trimEnd(u8, memory.written(), "\n"), .{});
    defer parsed.deinit();
    try testing.expectEqualDeep(version, runtime.currentConfiguration());
    try testing.expectEqual(@as(i64, @intCast(runtime.currentFilterGeneration())), parsed.value.object.get("config_generation").?.integer);
    try testing.expectEqualStrings("[REDACTED]", parsed.value.object.get("attributes").?.object.get("password").?.string);
}

test "filter reload supersedes full configuration and default-only changes retain scope overrides" {
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{.{ .name = "output", .sink = memory.sink() }} });
    defer runtime.destroy();
    _ = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = memory.sink() }}, .{ .default_filter = "off,hot=warn" });
    const log = runtime.scoped("hot");
    try testing.expect(!log.enabled(.debug));
    try runtime.reloadFilter("off,hot=debug");
    try testing.expect(log.enabled(.debug));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.debug, "reload works", .{}));
    try runtime.setLevelChecked(.trace);
    try testing.expect(log.enabled(.debug));
    try testing.expect(!log.enabled(.trace));
    try testing.expect(runtime.scoped("other").enabled(.trace));
    // Omitting default_filter in a subsequent route replacement inherits the
    // effective reload rather than restoring the initial library threshold.
    _ = try runtime.replaceConfiguration(&.{.{ .name = "output", .sink = memory.sink() }}, .{});
    try testing.expect(log.enabled(.debug));
    try testing.expect(runtime.scoped("other").enabled(.trace));
}

test "filter-only reload allocates nothing consumes no route slots and preserves sampling count" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const runtime = try kron.Runtime.create(failing.allocator(), testing.io, .{ .configuration_slots = 1, .sampling = .{ .count = 1 }, .routes = &.{.{ .name = "output", .sink = memory.sink() }} });
    defer runtime.destroy();
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    const log = runtime.scoped("hot");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "quota", .{}));
    const version = runtime.currentConfiguration();
    for (0..100) |_| {
        try runtime.reloadFilter("warn,hot=debug");
        try runtime.setLevelChecked(.info);
        try testing.expect(log.enabled(.debug));
    }
    try testing.expectEqual(kron.EmitResult.sampled, try log.tryEmit(.debug, "quota remains spent", .{}));
    try testing.expectEqualDeep(version, runtime.currentConfiguration());
    try testing.expect(!failing.has_induced_failure);
}

test "filter-only reload preserves every-two phase while complete policy resets it" {
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const route = kron.RouteOptions{ .name = "output", .sink = memory.sink() };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .sampling = .{ .every = 2 }, .routes = &.{route} });
    defer runtime.destroy();
    const log = runtime.scoped("phase");
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.info, "first", .{}));
    for (0..10) |_| {
        try runtime.reloadFilter("info,phase=debug");
        try runtime.setLevelChecked(.warn);
    }
    try testing.expectEqual(kron.EmitResult.sampled, try log.tryEmit(.debug, "second", .{}));
    _ = try runtime.replaceConfiguration(&.{route}, .{ .sampling = .{ .every = 2 }, .default_filter = "debug" });
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.debug, "new first", .{}));
    try testing.expectEqual(kron.EmitResult.sampled, try log.tryEmit(.debug, "new second", .{}));
    try testing.expectEqual(@as(usize, 2), memory.records);
}

test "failed complete transaction preserves filter generation and sink lease ownership" {
    const Owner = struct {
        releases: usize = 0,
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.releases += 1;
        }
    };
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    var owner: Owner = .{};
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .configuration_slots = 1, .filter = "off,hot=debug", .routes = &.{.{ .name = "output", .sink = memory.sink() }} });
    defer runtime.destroy();
    const version = runtime.currentConfiguration();
    const filter_generation = runtime.currentFilterGeneration();
    const route = kron.RouteOptions{ .name = "new", .sink = memory.sink(), .release = .{ .context = &owner, .release = Owner.release } };
    try testing.expectError(error.InvalidLevel, runtime.replaceConfigurationSources(&.{route}, .{ .explicit = .{ .filter_spec = "invalid" } }));
    try testing.expectError(error.ConfigSlotsExhausted, runtime.replaceConfigurationSources(&.{route}, .{ .explicit = .{ .filter_spec = "off" } }));
    try testing.expectEqualDeep(version, runtime.currentConfiguration());
    try testing.expectEqual(filter_generation, runtime.currentFilterGeneration());
    try testing.expectEqual(@as(usize, 0), owner.releases);
    try testing.expect(runtime.scoped("hot").enabled(.debug));
}

test "thread filter cache remains instance scope and route-generation bound" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [128]u8 = undefined;
    const journal_path = try std.fmt.bufPrint(&path, ".zig-cache/tmp/{s}/transaction.journal", .{tmp.sub_path});
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const route = kron.RouteOptions{ .name = "output", .sink = memory.sink(), .recovery_identity = "transaction-output" };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .submission = .low_latency, .journal = .{ .path = journal_path, .capacity = 8, .max_record_bytes = 1024 }, .max_thread_channels = 1, .thread_channel_capacity = 8, .routes = &.{route}, .filter = "off,first=debug" });
    defer runtime.destroy();
    const first = try runtime.attachThread(.{ .scope = "first" });
    try testing.expect(first.enabled(.debug));
    _ = try runtime.replaceConfiguration(&.{route}, .{ .default_filter = "off,first=warn,second=trace" });
    try testing.expect(!first.enabled(.debug));
    try runtime.reloadFilter("off,first=debug,second=trace");
    try testing.expect(first.enabled(.debug));
    try first.detach();
    const second = try runtime.attachThread(.{ .scope = "second" });
    defer second.detach() catch {};
    try testing.expect(second.enabled(.trace));
    try testing.expectEqual(kron.EmitResult.accepted, try second.tryEmit(.trace, "new owner", .{}));
    try runtime.flush(.written);
}

test "nested runtime guards keep the outer admitted filter decision across same-route reload" {
    const Guard = struct {
        runtime: *kron.Runtime,
        observed: bool = false,
        pub fn fields(self: *@This()) struct { guard: bool } {
            self.observed = self.runtime.scoped("outer").enabled(.debug);
            return .{ .guard = self.observed };
        }
    };
    const Outer = struct {
        runtime: *kron.Runtime,
        nested: *kron.Runtime,
        observed: bool = false,
        failure: ?anyerror = null,
        fn reload(runtime: *kron.Runtime, failure: *?anyerror) void {
            runtime.reloadFilter("off") catch |err| {
                failure.* = err;
            };
        }
        pub fn fields(self: *@This()) struct { preserved: bool } {
            const thread = std.Thread.spawn(.{}, reload, .{ self.runtime, &self.failure }) catch unreachable;
            thread.join();
            if (self.failure == null) {
                var guard: Guard = .{ .runtime = self.runtime };
                _ = self.nested.scoped("nested").tryEmitLazy(.info, "nested", &guard) catch unreachable;
                self.observed = guard.observed;
            }
            return .{ .preserved = self.observed };
        }
    };
    var outer_bytes: [8192]u8 = undefined;
    var nested_bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&outer_bytes);
    var nested_memory = kron.MemorySink.initBuffer(&nested_bytes);
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .filter = "off,outer=debug", .routes = &.{.{ .name = "outer", .sink = memory.sink() }} });
    defer runtime.destroy();
    const nested = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{.{ .name = "nested", .sink = nested_memory.sink() }} });
    defer nested.destroy();
    var provider: Outer = .{ .runtime = runtime, .nested = nested };
    try testing.expectEqual(kron.EmitResult.accepted, try runtime.scoped("outer").tryEmitLazy(.debug, "outer", &provider));
    if (provider.failure) |err| return err;
    try testing.expect(provider.observed);
    try testing.expect(!runtime.scoped("outer").enabled(.debug));
    try testing.expect(std.mem.indexOf(u8, memory.written(), "\"config_generation\":1") != null);
}

test "bounded JSON file installs a complete transaction and invalid file preserves live state" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/policy.json", .{tmp.sub_path});
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "policy.json", .data = "{\"filter\":\"off,hot=warn\",\"redaction\":[{\"key\":\"password\",\"action\":\"mask\"}],\"predicate\":\"status >= 500\",\"sampling\":{\"kind\":\"every\",\"every\":2}}" });
    var bytes: [8192]u8 = undefined;
    var memory = kron.MemorySink.initBuffer(&bytes);
    const route = kron.RouteOptions{ .name = "output", .sink = memory.sink() };
    const runtime = try kron.Runtime.create(testing.allocator, testing.io, .{ .routes = &.{route} });
    defer runtime.destroy();
    const version = try runtime.replaceConfigurationFile(&.{route}, path, .{ .environment = kron.configuration_sources.fromEntries(&.{.{ .key = "KRON_LOG", .value = "off,hot=debug" }}) });
    const log = runtime.scoped("hot");
    try testing.expect(log.enabled(.debug));
    try testing.expectEqual(kron.EmitResult.accepted, try log.tryEmit(.debug, "file policy", .{ .password = "private", .status = @as(u16, 503) }));
    try testing.expectEqual(kron.EmitResult.sampled, try log.tryEmit(.debug, "sampled", .{ .status = @as(u16, 503) }));
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "policy.json", .data = "{\"filter\":\"off\",\"unknown\":true}" });
    try testing.expectError(error.UnknownField, runtime.replaceConfigurationFile(&.{route}, path, .{}));
    try testing.expectEqualDeep(version, runtime.currentConfiguration());
    try testing.expect(log.enabled(.debug));
    try testing.expect(std.mem.indexOf(u8, memory.written(), "[REDACTED]") != null);
}
