//! Typed capture once, admission and submission into independent pipelines.
const std = @import("std");
const logging = @import("root.zig");
const Runtime = @import("../core/runtime.zig").Runtime;
const core = @import("../core/logger.zig");
const threads = @import("../core/thread_registry.zig");
pub const ThreadLogger = core.Logger(threads.ThreadOwner(Runtime), .trace);
pub const Token = struct { slot: usize, generation: usize, thread: std.Thread.Id };
pub const Outcome = union(enum) { result: core.EmitResult, err: anyerror };
pub const Site = struct { next: ?*Site = null, bindings: []?@import("../core/prepared.zig").Binding };
const Frame = struct {
    owner: *logging.Logging = undefined,
    admissions: [64]core.Admission = undefined,
    selected: u64 = 0,
    results: [64]Outcome = @splat(.{ .result = .filtered }),
};
const Frames = struct {
    threadlocal var stack: [8]Frame = undefined;
    threadlocal var depth: usize = 0;
    threadlocal var last_owner: ?*logging.Logging = null;
    threadlocal var last: [64]Outcome = @splat(.{ .result = .filtered });
};
pub fn lastResults(owner: *logging.Logging) []const Outcome {
    return if (Frames.last_owner == owner) Frames.last[0..owner.pipelines.len] else &.{};
}
fn publish(owner: *logging.Logging, results: []const Outcome) void {
    Frames.last_owner = owner;
    @memcpy(Frames.last[0..results.len], results);
}
pub const Owner = struct {
    pub const value_owner = true;
    pub const AdmissionType = struct {
        route_mask: u64 = 1,
        config_generation: u64 = 0,
        frame: ?*Frame = null,
    };
    pub const BeginResult = union(enum) { ready: AdmissionType, filtered, sampled, closed };
    logging: *logging.Logging,
    scope: []const u8,
    mask: u64,
    token: ?Token = null,
    site: ?*Site = null,

    fn valid(self: Owner) !void {
        if (self.token) |token| {
            if (token.thread != std.Thread.getCurrentId()) return error.WrongThread;
            const slot = &self.logging.attachments[token.slot];
            if (!slot.busy.load(.acquire) or slot.generation.load(.acquire) != token.generation) return error.StaleToken;
        }
    }
    fn threadHandle(self: Owner, index: usize) ?ThreadLogger {
        if (self.token) |token| return self.logging.thread_handles[token.slot * self.logging.pipelines.len + index];
        return null;
    }
    pub fn enabled(self: Owner, level: core.Level, scope: []const u8) bool {
        self.valid() catch return false;
        for (self.logging.pipelines, 0..) |pipeline, i| {
            if (self.mask & (@as(u64, 1) << @intCast(i)) == 0) continue;
            if (self.threadHandle(i)) |thread| {
                if (thread.enabled(level)) return true;
            } else if (pipeline.runtime.enabled(level, scope)) return true;
        }
        return false;
    }
    fn beginOne(self: Owner, i: usize, level: core.Level, scope: []const u8) core.BeginResult {
        if (self.threadHandle(i)) |thread| return thread.owner.begin(level, thread.scope);
        return self.logging.pipelines[i].runtime.begin(level, scope);
    }
    fn endOne(self: Owner, i: usize) void {
        if (self.threadHandle(i)) |thread| thread.owner.end() else self.logging.pipelines[i].runtime.end();
    }
    fn rejected(self: Owner) BeginResult {
        Frames.last_owner = self.logging;
        @memset(Frames.last[0..self.logging.pipelines.len], .{ .result = .rejected_closing });
        return .closed;
    }
    pub fn begin(self: Owner, level: core.Level, scope: []const u8) BeginResult {
        self.valid() catch |err| {
            self.reportError(err);
            return self.rejected();
        };
        for (Frames.stack[0..Frames.depth]) |*active| if (active.owner == self.logging) return self.rejected();
        if (Frames.depth == Frames.stack.len) return self.rejected();
        const frame = &Frames.stack[Frames.depth];
        frame.owner = self.logging;
        frame.selected = 0;
        @memset(frame.results[0..self.logging.pipelines.len], .{ .result = .filtered });
        Frames.depth += 1;
        if (self.logging.stopping.load(.acquire)) {
            @memset(frame.results[0..self.logging.pipelines.len], .{ .result = .rejected_closing });
            Frames.depth -= 1;
            publish(self.logging, frame.results[0..self.logging.pipelines.len]);
            return .closed;
        }
        if (@popCount(self.mask) == 1) {
            const i: usize = @intCast(@ctz(self.mask));
            switch (self.beginOne(i, level, scope)) {
                .ready => |admission| {
                    frame.selected = self.mask;
                    frame.admissions[i] = admission;
                    return .{ .ready = .{ .route_mask = admission.route_mask, .config_generation = admission.config_generation, .frame = frame } };
                },
                .filtered => {},
                .sampled => frame.results[i] = .{ .result = .sampled },
                .closed => frame.results[i] = .{ .result = .rejected_closing },
            }
            Frames.depth -= 1;
            publish(self.logging, frame.results[0..self.logging.pipelines.len]);
            return switch (frame.results[i].result) {
                .sampled => .sampled,
                .rejected_closing => .closed,
                else => .filtered,
            };
        }
        var sampled = false;
        var closed = false;
        for (self.logging.pipelines, 0..) |_, i| {
            const bit = @as(u64, 1) << @intCast(i);
            if (self.mask & bit == 0) continue;
            switch (self.beginOne(i, level, scope)) {
                .ready => |admission| {
                    frame.admissions[i] = admission;
                    frame.selected |= bit;
                },
                .filtered => {},
                .sampled => {
                    sampled = true;
                    frame.results[i] = .{ .result = .sampled };
                },
                .closed => {
                    closed = true;
                    frame.results[i] = .{ .result = .rejected_closing };
                },
            }
        }
        if (frame.selected != 0) return .{ .ready = .{ .frame = frame } };
        Frames.depth -= 1;
        publish(self.logging, frame.results[0..self.logging.pipelines.len]);
        return if (closed) .closed else if (sampled) .sampled else .filtered;
    }
    pub fn endAdmission(self: Owner, admission: AdmissionType) void {
        const frame = admission.frame.?;
        if (@popCount(self.mask) == 1) {
            self.endOne(@intCast(@ctz(self.mask)));
        } else {
            var i = self.logging.pipelines.len;
            while (i != 0) {
                i -= 1;
                if (frame.selected & (@as(u64, 1) << @intCast(i)) != 0) self.endOne(i);
            }
        }
        std.debug.assert(Frames.depth != 0 and frame == &Frames.stack[Frames.depth - 1]);
        Frames.depth -= 1;
        publish(self.logging, frame.results[0..self.logging.pipelines.len]);
    }
    pub fn nowNs(self: Owner) i64 {
        return self.logging.pipelines[@ctz(self.mask)].runtime.nowNs();
    }
    fn submitOne(self: Owner, i: usize, admission: core.Admission, event: core.Event) !core.EmitResult {
        const binding = if (self.site) |site| site.bindings[i] else null;
        if (self.threadHandle(i)) |thread| return if (binding) |schema| thread.owner.submitWithSchema(admission, event, schema) else thread.owner.submit(admission, event);
        const runtime = self.logging.pipelines[i].runtime;
        return if (binding) |schema| runtime.submitWithSchema(admission, event, schema) else runtime.submit(admission, event);
    }
    pub fn submit(self: Owner, admission: AdmissionType, event: core.Event) !core.EmitResult {
        if (@popCount(self.mask) == 1) {
            const i: usize = @intCast(@ctz(self.mask));
            const frame = admission.frame.?;
            const result = self.submitOne(i, frame.admissions[i], event) catch |err| {
                frame.results[i] = .{ .err = err };
                const pipeline = self.logging.pipelines[i];
                pipeline.runtime.reportError(err);
                if (pipeline.delivery == .required) return err;
                return .filtered;
            };
            frame.results[i] = .{ .result = result };
            return result;
        }
        const frame = admission.frame.?;
        var accepted = false;
        var aggregate: core.EmitResult = .filtered;
        var failure: ?anyerror = null;
        for (self.logging.pipelines, 0..) |pipeline, i| {
            if (frame.selected & (@as(u64, 1) << @intCast(i)) == 0) continue;
            const result = self.submitOne(i, frame.admissions[i], event) catch |err| {
                frame.results[i] = .{ .err = err };
                pipeline.runtime.reportError(err);
                if (pipeline.delivery == .required and failure == null) failure = err;
                continue;
            };
            frame.results[i] = .{ .result = result };
            if (result == .accepted) accepted = true else if (aggregate == .filtered) aggregate = result;
        }
        if (failure) |err| return err;
        return if (accepted) .accepted else aggregate;
    }
    pub fn captureFailed(self: Owner, err: anyerror) void {
        if (Frames.depth == 0) return;
        const frame = &Frames.stack[Frames.depth - 1];
        for (self.logging.pipelines, 0..) |pipeline, i| if (frame.selected & (@as(u64, 1) << @intCast(i)) != 0) {
            frame.results[i] = .{ .err = err };
            pipeline.runtime.captureFailed(err);
        };
    }
    pub fn reportError(self: Owner, err: anyerror) void {
        // Frontend void methods report the aggregate error after the result
        // has been published. Keep a failed output's diagnostic local.
        if (Frames.last_owner == self.logging) {
            var recorded = false;
            for (Frames.last[0..self.logging.pipelines.len], self.logging.pipelines) |outcome, pipeline| {
                if (outcome == .err and outcome.err == err) {
                    pipeline.runtime.reportError(err);
                    recorded = true;
                }
            }
            if (recorded) return;
        }
        for (self.logging.pipelines, 0..) |pipeline, i| if (self.mask & (@as(u64, 1) << @intCast(i)) != 0) pipeline.runtime.reportError(err);
    }
    pub fn copyScope(self: Owner, destination: []u8) ![]const u8 {
        try self.valid();
        if (self.token == null) {
            if (destination.len < self.scope.len) return error.BufferTooSmall;
            @memcpy(destination[0..self.scope.len], self.scope);
            return destination[0..self.scope.len];
        }
        const slot = &self.logging.attachments[self.token.?.slot];
        if (destination.len < slot.scope_len) return error.BufferTooSmall;
        @memcpy(destination[0..slot.scope_len], slot.scope[0..slot.scope_len]);
        return destination[0..slot.scope_len];
    }
    pub fn detach(self: Owner) !void {
        try self.valid();
        const token = self.token orelse return error.ThreadChannelsDisabled;
        for (Frames.stack[0..Frames.depth]) |*frame| if (frame.owner == self.logging) return error.OutstandingAdmission;
        var i = self.logging.pipelines.len;
        while (i != 0) {
            i -= 1;
            const position = token.slot * self.logging.pipelines.len + i;
            if (self.threadHandle(i)) |thread| {
                try thread.detach();
                // A retry may finish remaining channels after a concurrent shutdown.
                self.logging.thread_handles[position] = null;
            }
        }
        self.logging.attachment_mutex.lockUncancelable(self.logging.io);
        defer self.logging.attachment_mutex.unlock(self.logging.io);
        for (self.logging.thread_handles[token.slot * self.logging.pipelines.len ..][0..self.logging.pipelines.len]) |*thread| thread.* = null;
        self.logging.attachments[token.slot].busy.store(false, .release);
    }
};
