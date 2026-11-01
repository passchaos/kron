//! Generic, allocation-free producer frontend. Owner admission precedes field
//! capture and clocks; Owner.submit must copy every borrowed value before it
//! returns accepted. Ordinary methods report errors through the owner's hook.
const std = @import("std");
const contexts = @import("context.zig");
const fields = @import("field.zig");
const deferred_format = @import("../submit/format.zig");
pub const Level = @import("level.zig").Level;
pub const Event = @import("event.zig").Event;
pub const TraceContext = @import("../telemetry/trace_context.zig").TraceContext;
pub const Field = fields.Field;

pub const EmitResult = enum {
    accepted,
    filtered,
    sampled,
    dropped_full,
    dropped_oversize,
    rejected_closing,
};

pub const Admission = struct {
    route_mask: u64,
    config_generation: u64,
    route_generation: u64 = 0,
    route_fingerprint: u64 = 0,
};
pub const BeginResult = union(enum) { ready: Admission, filtered, sampled, closed };

/// Zig has no default function parameters. Runtime factories instantiate this
/// with .trace unless the application selects a higher static minimum.
pub fn Logger(comptime Owner: type, comptime min_level: Level) type {
    return Frontend(Owner, min_level, contexts.EmptyContext);
}

pub fn ChildLogger(comptime Parent: type, comptime Input: type) type {
    return Frontend(Parent.OwnerType, Parent.minimum_level, contexts.BorrowedContext(Parent.ContextType, Input));
}

pub fn OwnedLogger(comptime Parent: type) type {
    return Frontend(Parent.OwnerType, Parent.minimum_level, contexts.OwnedContext);
}

fn Frontend(comptime Owner: type, comptime min_level: Level, comptime Context: type) type {
    return struct {
        const Self = @This();
        pub const OwnerType = Owner;
        pub const OwnerStorage = if (@hasDecl(Owner, "value_owner")) (if (Owner.value_owner) Owner else *Owner) else *Owner;
        pub const ContextType = Context;
        pub const minimum_level = min_level;

        owner: OwnerStorage,
        scope: []const u8,
        context: Context = if (Context == contexts.EmptyContext) .{} else undefined,
        trace_context: ?TraceContext = null,

        pub fn init(owner: OwnerStorage, scope: []const u8) Self {
            if (Context != contexts.EmptyContext) @compileError("child loggers must be created using withBorrowed/withOwned");
            return .{ .owner = owner, .scope = scope };
        }

        pub fn comptimeEnabled(comptime level: Level) bool {
            return min_level.allows(level);
        }

        /// This check does not capture fields or consume a sampler decision.
        /// Arguments to a subsequent log call still evaluate before that call.
        pub fn enabled(self: Self, level: Level) bool {
            return min_level.allows(level) and self.owner.enabled(level, self.scope);
        }

        /// Copies the scope into caller storage. Thread owners validate their
        /// attachment instead of exposing a reused channel's internal slice.
        pub fn copyScope(self: Self, destination: []u8) anyerror![]const u8 {
            if (@hasDecl(Owner, "copyScope")) return self.owner.copyScope(destination);
            if (destination.len < self.scope.len) return error.BufferTooSmall;
            @memcpy(destination[0..self.scope.len], self.scope);
            return destination[0..self.scope.len];
        }

        pub fn withBorrowed(self: Self, input: anytype) ChildLogger(Self, @TypeOf(input)) {
            return .{
                .owner = self.owner,
                .scope = self.scope,
                .context = .{ .parent = self.context, .fields = input },
                .trace_context = self.trace_context,
            };
        }

        /// Deep-copies the entire merged context, including any borrowed
        /// parents. The resulting logger owns no borrowed field storage.
        pub fn withOwned(self: Self, allocator: std.mem.Allocator, input: anytype) !OwnedLogger(Self) {
            var scratch: [contexts.max_fields]Field = undefined;
            var count: usize = 0;
            try self.appendContext(&scratch, &count);
            try contexts.mergeFields(&scratch, &count, input);
            return .{
                .owner = self.owner,
                .scope = self.scope,
                .context = try contexts.OwnedContext.init(allocator, scratch[0..count]),
                .trace_context = self.trace_context,
            };
        }

        /// Trace context is copied by value and propagates to derived loggers.
        /// When this logger owns context, the returned value shares ownership;
        /// destroy only the original owner after all derived users finish.
        pub fn withTrace(self: Self, trace_value: TraceContext) Self {
            var child = self;
            child.trace_context = trace_value;
            return child;
        }

        pub fn appendContext(self: Self, destination: []Field, count: *usize) contexts.MergeError!void {
            try self.context.appendContext(destination, count);
        }

        pub fn destroy(self: *Self) void {
            if (Context != contexts.OwnedContext) @compileError("only withOwned loggers own context; borrowed loggers need no destroy");
            self.context.destroy();
        }

        pub fn deinit(self: *Self) void {
            self.destroy();
        }

        /// Thread frontends carry their attachment token by value. Copies of
        /// a handle share that attachment and become stale after its detach.
        pub fn detach(self: Self) anyerror!void {
            if (!@hasDecl(Owner, "detach")) @compileError("this logger owner has no thread attachment to detach");
            try self.owner.detach();
        }

        pub fn log(self: Self, level: Level, message: []const u8, input: anytype) void {
            _ = self.tryEmit(level, message, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn tryEmit(self: Self, level: Level, message: []const u8, input: anytype) anyerror!EmitResult {
            return self.tryEmitAt(null, level, message, input);
        }

        pub fn tryEmitAt(self: Self, source: ?std.builtin.SourceLocation, level: Level, message: []const u8, input: anytype) anyerror!EmitResult {
            const admission = switch (self.begin(level)) {
                .ready => |value| value,
                .filtered => return .filtered,
                .sampled => return .sampled,
                .closed => return .rejected_closing,
            };
            defer self.owner.end();
            return self.captureAndSubmit(admission, source, level, message, input, false, &.{});
        }

        pub fn logAt(self: Self, source: std.builtin.SourceLocation, level: Level, message: []const u8, input: anytype) void {
            _ = self.tryEmitAt(source, level, message, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn logf(self: Self, level: Level, comptime fmt: []const u8, args: anytype, input: anytype) void {
            _ = self.tryLogf(level, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn tryLogf(self: Self, level: Level, comptime fmt: []const u8, args: anytype, input: anytype) anyerror!EmitResult {
            return self.tryLogfAt(null, level, fmt, args, input);
        }

        pub fn tryLogfAt(self: Self, source: ?std.builtin.SourceLocation, level: Level, comptime fmt: []const u8, args: anytype, input: anytype) anyerror!EmitResult {
            comptime deferred_format.validate(fmt, @TypeOf(args));
            const admission = switch (self.begin(level)) {
                .ready => |value| value,
                .filtered => return .filtered,
                .sampled => return .sampled,
                .closed => return .rejected_closing,
            };
            defer self.owner.end();
            var arguments: [deferred_format.max_args]Field = undefined;
            const captured = deferred_format.capture(fmt, args, &arguments) catch |capture_error| {
                self.owner.captureFailed(capture_error);
                return capture_error;
            };
            return self.captureAndSubmit(admission, source, level, fmt, input, true, captured);
        }

        /// Explicit producer formatting supports custom {f} formatters. The
        /// caller controls the byte budget; there is no implicit allocation.
        pub fn tryLogfPreencoded(self: Self, level: Level, buffer: []u8, comptime fmt: []const u8, args: anytype, input: anytype) anyerror!EmitResult {
            const admission = switch (self.begin(level)) {
                .ready => |value| value,
                .filtered => return .filtered,
                .sampled => return .sampled,
                .closed => return .rejected_closing,
            };
            defer self.owner.end();
            const message = std.fmt.bufPrint(buffer, fmt, args) catch |capture_error| {
                self.owner.captureFailed(capture_error);
                return capture_error;
            };
            return self.captureAndSubmit(admission, null, level, message, input, false, &.{});
        }

        pub fn logfPreencoded(self: Self, level: Level, buffer: []u8, comptime fmt: []const u8, args: anytype, input: anytype) void {
            _ = self.tryLogfPreencoded(level, buffer, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        /// A provider exposes fields() and runs only after successful
        /// admission, so filtering and sampling skip expensive construction.
        pub fn tryEmitLazy(self: Self, level: Level, message: []const u8, provider: anytype) anyerror!EmitResult {
            const admission = switch (self.begin(level)) {
                .ready => |value| value,
                .filtered => return .filtered,
                .sampled => return .sampled,
                .closed => return .rejected_closing,
            };
            defer self.owner.end();
            return self.captureAndSubmit(admission, null, level, message, provider.fields(), false, &.{});
        }

        pub fn logLazy(self: Self, level: Level, message: []const u8, provider: anytype) void {
            _ = self.tryEmitLazy(level, message, provider) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn trace(self: Self, message: []const u8, input: anytype) void {
            if (comptime !comptimeEnabled(.trace)) return;
            self.log(.trace, message, input);
        }

        pub fn debug(self: Self, message: []const u8, input: anytype) void {
            if (comptime !comptimeEnabled(.debug)) return;
            self.log(.debug, message, input);
        }

        pub fn info(self: Self, message: []const u8, input: anytype) void {
            if (comptime !comptimeEnabled(.info)) return;
            self.log(.info, message, input);
        }

        pub fn warn(self: Self, message: []const u8, input: anytype) void {
            if (comptime !comptimeEnabled(.warn)) return;
            self.log(.warn, message, input);
        }

        pub fn err(self: Self, message: []const u8, input: anytype) void {
            if (comptime !comptimeEnabled(.err)) return;
            self.log(.err, message, input);
        }

        pub fn fatal(self: Self, message: []const u8, input: anytype) void {
            if (comptime !comptimeEnabled(.fatal)) return;
            self.log(.fatal, message, input);
        }

        pub fn traceAt(self: Self, source: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, input: anytype) void {
            if (comptime !comptimeEnabled(.trace)) return;
            _ = self.tryLogfAt(source, .trace, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn debugAt(self: Self, source: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, input: anytype) void {
            if (comptime !comptimeEnabled(.debug)) return;
            _ = self.tryLogfAt(source, .debug, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn infoAt(self: Self, source: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, input: anytype) void {
            if (comptime !comptimeEnabled(.info)) return;
            _ = self.tryLogfAt(source, .info, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn warnAt(self: Self, source: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, input: anytype) void {
            if (comptime !comptimeEnabled(.warn)) return;
            _ = self.tryLogfAt(source, .warn, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn errAt(self: Self, source: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, input: anytype) void {
            if (comptime !comptimeEnabled(.err)) return;
            _ = self.tryLogfAt(source, .err, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        pub fn fatalAt(self: Self, source: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, input: anytype) void {
            if (comptime !comptimeEnabled(.fatal)) return;
            _ = self.tryLogfAt(source, .fatal, fmt, args, input) catch |emit_error| {
                self.owner.reportError(emit_error);
                return;
            };
        }

        fn begin(self: Self, level: Level) BeginResult {
            if (!min_level.allows(level)) return .filtered;
            return self.owner.begin(level, self.scope);
        }

        fn captureAndSubmit(self: Self, admission: Admission, source: ?std.builtin.SourceLocation, level: Level, message: []const u8, input: anytype, message_template: bool, format_args: []const Field) anyerror!EmitResult {
            const Input = @TypeOf(input);
            const capacity = comptime if (Context == contexts.EmptyContext) switch (@typeInfo(Input)) {
                .@"struct" => |input_info| @min(input_info.fields.len, contexts.max_fields),
                else => contexts.max_fields,
            } else contexts.max_fields;
            var captured: [capacity]Field = undefined;
            var count: usize = 0;
            if (comptime Context == contexts.EmptyContext) {
                // No parent fields exist, so capture into the final descriptor
                // array instead of creating and merging a second context layer.
                fields.appendFields(&captured, &count, input) catch |capture_error| {
                    self.owner.captureFailed(capture_error);
                    return capture_error;
                };
            } else {
                self.appendContext(&captured, &count) catch |capture_error| {
                    self.owner.captureFailed(capture_error);
                    return capture_error;
                };
                contexts.mergeFields(&captured, &count, input) catch |capture_error| {
                    self.owner.captureFailed(capture_error);
                    return capture_error;
                };
            }
            var event: Event = .{
                .level = level,
                .scope = self.scope,
                .message = message,
                .message_template = message_template,
                .format_args = format_args,
                .fields = captured[0..count],
                .timestamp_ns = self.owner.nowNs(),
                .route_mask = admission.route_mask,
                .config_generation = admission.config_generation,
                .source = source,
            };
            if (self.trace_context) |context| {
                event.trace_id = context.trace_id;
                event.span_id = context.span_id;
                if (@hasField(Event, "trace_flags")) event.trace_flags = context.flags;
            }
            return self.owner.submit(admission, event);
        }
    };
}

const TestOwner = struct {
    io: std.Io = std.testing.io,
    admission: BeginResult = .{ .ready = .{ .route_mask = 5, .config_generation = 7 } },
    begins: usize = 0,
    ends: usize = 0,
    clocks: usize = 0,
    submissions: usize = 0,
    capture_failures: usize = 0,
    reported_errors: usize = 0,
    submit_error: bool = false,
    result: EmitResult = .accepted,
    last: Event = undefined,
    last_fields: [contexts.max_fields]Field = undefined,
    last_args: [deferred_format.max_args]Field = undefined,

    pub fn enabled(self: *TestOwner, _: Level, _: []const u8) bool {
        return self.admission == .ready;
    }

    pub fn begin(self: *TestOwner, _: Level, _: []const u8) BeginResult {
        self.begins += 1;
        return self.admission;
    }

    pub fn end(self: *TestOwner) void {
        self.ends += 1;
    }

    pub fn nowNs(self: *TestOwner) i64 {
        self.clocks += 1;
        return 123;
    }

    pub fn submit(self: *TestOwner, _: Admission, event: Event) anyerror!EmitResult {
        self.submissions += 1;
        if (self.submit_error) return error.SinkFailed;
        self.last = event;
        @memcpy(self.last_fields[0..event.fields.len], event.fields);
        @memcpy(self.last_args[0..event.format_args.len], event.format_args);
        self.last.fields = self.last_fields[0..event.fields.len];
        self.last.format_args = self.last_args[0..event.format_args.len];
        return self.result;
    }

    pub fn captureFailed(self: *TestOwner, _: anyerror) void {
        self.capture_failures += 1;
    }

    pub fn reportError(self: *TestOwner, _: anyerror) void {
        self.reported_errors += 1;
    }
};

test "admission skips capture and clock; every ready admission ends on failure" {
    var owner: TestOwner = .{};
    const log = Logger(TestOwner, .info).init(&owner, "test");
    try std.testing.expect(!Logger(TestOwner, .info).comptimeEnabled(.debug));
    try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.debug, "unused", .{}));
    try std.testing.expectEqual(@as(usize, 0), owner.begins);
    const duplicate: []const Field = &.{ fields.kv("a", 1), fields.kv("a", 2) };
    owner.admission = .filtered;
    try std.testing.expectEqual(EmitResult.filtered, try log.tryEmit(.info, "unused", duplicate));
    owner.admission = .sampled;
    try std.testing.expectEqual(EmitResult.sampled, try log.tryEmit(.info, "unused", duplicate));
    owner.admission = .closed;
    try std.testing.expectEqual(EmitResult.rejected_closing, try log.tryEmit(.info, "unused", duplicate));
    try std.testing.expectEqual(@as(usize, 0), owner.clocks);
    try std.testing.expectEqual(@as(usize, 0), owner.capture_failures);
    try std.testing.expectEqual(@as(usize, 0), owner.ends);
    owner.admission = .{ .ready = .{ .route_mask = 5, .config_generation = 7 } };
    try std.testing.expectError(error.DuplicateKey, log.tryEmit(.info, "invalid", duplicate));
    try std.testing.expectEqual(@as(usize, 1), owner.ends);
    try std.testing.expectEqual(@as(usize, 1), owner.capture_failures);
    try std.testing.expectEqual(@as(usize, 0), owner.clocks);
    owner.submit_error = true;
    log.info("failed", .{});
    try std.testing.expectEqual(@as(usize, 2), owner.ends);
    try std.testing.expectEqual(@as(usize, 1), owner.reported_errors);
    try std.testing.expectError(error.SinkFailed, log.tryEmit(.err, "failed", .{}));
    try std.testing.expectEqual(@as(usize, 3), owner.ends);
}

test "nested borrowed context, owned parent snapshot and explicit trace propagation" {
    var owner: TestOwner = .{};
    const log = Logger(TestOwner, .trace).init(&owner, "http");
    var text = [_]u8{ 'b', 'e', 'f', 'o', 'r', 'e' };
    var layer = [_]Field{ fields.kv("request", 1), fields.kv("name", @as([]const u8, &text)) };
    const parent = log.withBorrowed(@as([]const Field, &layer));
    const child = parent.withBorrowed(.{ .request = 2, .child = true }).withTrace(.{
        .trace_id = .{1} ** 16,
        .span_id = .{2} ** 8,
        .flags = 1,
    });
    var owned = try child.withOwned(std.testing.allocator, .{ .owned = true });
    defer owned.destroy();
    @memset(&text, 'x');
    layer[0] = fields.kv("request", 99);
    try std.testing.expectEqual(EmitResult.accepted, try owned.tryEmit(.info, "completed", .{ .request = 3 }));
    try std.testing.expectEqual(@as(usize, 4), owner.last.fields.len);
    try std.testing.expectEqual(@as(u128, 3), owner.last.fields[0].value.unsigned);
    try std.testing.expectEqualStrings("before", owner.last.fields[1].value.string);
    try std.testing.expectEqual(@as(u64, 5), owner.last.route_mask);
    try std.testing.expectEqual(@as(u64, 7), owner.last.config_generation);
    try std.testing.expectEqual(@as(i64, 123), owner.last.timestamp_ns);
    try std.testing.expectEqualSlices(u8, &(.{1} ** 16), &owner.last.trace_id.?);
    try std.testing.expectEqualSlices(u8, &(.{2} ** 8), &owner.last.span_id.?);
    try std.testing.expectEqual(@as(u8, 1), owner.last.trace_flags);
}

test "typed logf retains template and source rather than formatting on producer" {
    var owner: TestOwner = .{};
    const log = Logger(TestOwner, .trace).init(&owner, "test");
    var scope_copy: [8]u8 = undefined;
    try std.testing.expectEqualStrings("test", try log.copyScope(&scope_copy));
    const source = @src();
    log.infoAt(source, "request {d}: {s}", .{ @as(u16, 42), "done" }, .{ .status = 200 });
    try std.testing.expect(owner.last.message_template);
    try std.testing.expectEqualStrings("request {d}: {s}", owner.last.message);
    try std.testing.expectEqual(@as(usize, 2), owner.last.format_args.len);
    try std.testing.expectEqual(@as(u128, 42), owner.last.format_args[0].value.unsigned);
    try std.testing.expectEqualStrings("done", owner.last.format_args[1].value.string);
    try std.testing.expectEqual(source.line, owner.last.source.?.line);
    try std.testing.expectEqual(@as(usize, 1), owner.ends);
}

test "enabled and lazy guards do not construct skipped fields" {
    const Provider = struct {
        calls: *usize,
        pub fn fields(self: @This()) struct { answer: u16 } {
            self.calls.* += 1;
            return .{ .answer = 42 };
        }
    };
    var owner: TestOwner = .{ .admission = .sampled };
    const log = Logger(TestOwner, .trace).init(&owner, "test");
    var calls: usize = 0;
    try std.testing.expect(!log.enabled(.info));
    try std.testing.expectEqual(@as(usize, 0), owner.begins);
    try std.testing.expectEqual(EmitResult.sampled, try log.tryEmitLazy(.info, "unused", Provider{ .calls = &calls }));
    try std.testing.expectEqual(@as(usize, 0), calls);
    owner.admission = .{ .ready = .{ .route_mask = 1, .config_generation = 1 } };
    try std.testing.expectEqual(EmitResult.accepted, try log.tryEmitLazy(.info, "built", Provider{ .calls = &calls }));
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expectEqual(@as(usize, 1), owner.ends);
}

test "explicit preencoding supports custom formatter and obeys admission" {
    const Custom = struct {
        pub fn format(_: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.writeAll("custom");
        }
    };
    var owner: TestOwner = .{};
    const log = Logger(TestOwner, .trace).init(&owner, "test");
    var bytes: [32]u8 = undefined;
    try std.testing.expectEqual(EmitResult.accepted, try log.tryLogfPreencoded(.info, &bytes, "value {f}", .{Custom{}}, .{}));
    try std.testing.expectEqualStrings("value custom", owner.last.message);
    try std.testing.expect(!owner.last.message_template);
    var tiny: [1]u8 = undefined;
    try std.testing.expectError(error.NoSpaceLeft, log.tryLogfPreencoded(.info, &tiny, "{f}", .{Custom{}}, .{}));
    try std.testing.expectEqual(@as(usize, 2), owner.ends);
    try std.testing.expectEqual(@as(usize, 1), owner.capture_failures);
}

test "static level methods erase capture and owned emits allocate nothing" {
    var owner: TestOwner = .{};
    const log = Logger(TestOwner, .info).init(&owner, "test");
    // Arbitrary pointers cannot be captured. This compiles because the debug
    // method does not instantiate capture below its static minimum.
    log.debug("unused", .{ .pointer = &owner });
    try std.testing.expectEqual(@as(usize, 0), owner.begins);
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    var owned = try log.withOwned(allocator.allocator(), .{ .name = "context" });
    defer owned.destroy();
    const allocations = allocator.allocations;
    try std.testing.expectEqual(EmitResult.accepted, try owned.tryLogf(.info, "answer {d}", .{@as(u16, 42)}, .{ .answer = 42 }));
    try std.testing.expectEqual(allocations, allocator.allocations);
    try std.testing.expect(!allocator.has_induced_failure);
}
