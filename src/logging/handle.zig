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
const Fanout = struct {
    admissions: [64]core.Admission = undefined,
    selected: u64 = 0,
    results: [64]Outcome = @splat(.{ .result = .filtered }),
};
const Frame = struct {
    owner: *logging.Logging,
    admission: core.Admission = undefined,
    outcome: Outcome = .{ .result = .filtered },
    fanout: ?*Fanout = null,
};
const Frames = struct {
    threadlocal var stack: [8]Frame = undefined;
    threadlocal var fanouts: [8]Fanout = undefined;
    threadlocal var depth: usize = 0;
    threadlocal var last_owner: ?*logging.Logging = null;
    threadlocal var last: [64]Outcome = @splat(.{ .result = .filtered });
};
pub fn lastResults(owner: *logging.Logging) []const Outcome {
    return if (Frames.last_owner == owner) Frames.last[0..owner.pipelines.len] else &.{};
}
fn publish(frame: *const Frame) void {
    Frames.last_owner = frame.owner;
    if (frame.fanout) |fanout| {
        @memcpy(Frames.last[0..frame.owner.pipelines.len], fanout.results[0..frame.owner.pipelines.len]);
    } else Frames.last[0] = frame.outcome;
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
    token: ?Token = null,
    site: ?*Site = null,

    fn valid(self: *const Owner) !void {
        if (self.token) |token| {
            if (token.thread != std.Thread.getCurrentId()) return error.WrongThread;
            const slot = &self.logging.attachments[token.slot];
            if (!slot.busy.load(.acquire) or slot.generation.load(.acquire) != token.generation) return error.StaleToken;
        }
    }
    fn threadHandle(self: *const Owner, index: usize) ?ThreadLogger {
        if (self.token) |token| return self.logging.thread_handles[token.slot * self.logging.pipelines.len + index];
        return null;
    }
    pub fn enabled(self: *const Owner, level: core.Level, scope: []const u8) bool {
        self.valid() catch return false;
        for (self.logging.pipelines, 0..) |pipeline, i| {
            if (self.threadHandle(i)) |thread| {
                if (thread.enabled(level)) return true;
            } else if (pipeline.runtime.enabled(level, scope)) return true;
        }
        return false;
    }
    fn beginOne(self: *const Owner, i: usize, level: core.Level, scope: []const u8) core.BeginResult {
        if (self.threadHandle(i)) |thread| return thread.owner.begin(level, thread.scope);
        return self.logging.pipelines[i].runtime.begin(level, scope);
    }
    fn endOne(self: *const Owner, i: usize) void {
        if (self.threadHandle(i)) |thread| thread.owner.end() else self.logging.pipelines[i].runtime.end();
    }
    fn rejected(self: *const Owner) BeginResult {
        Frames.last_owner = self.logging;
        @memset(Frames.last[0..self.logging.pipelines.len], .{ .result = .rejected_closing });
        return .closed;
    }
    pub fn begin(self: *const Owner, level: core.Level, scope: []const u8) BeginResult {
        self.valid() catch |err| {
            self.reportError(err);
            return self.rejected();
        };
        for (Frames.stack[0..Frames.depth]) |*active| if (active.owner == self.logging) return self.rejected();
        if (Frames.depth == Frames.stack.len) return self.rejected();
        const frame = &Frames.stack[Frames.depth];
        frame.* = .{ .owner = self.logging };
        Frames.depth += 1;
        if (self.logging.stopping.load(.acquire)) {
            Frames.depth -= 1;
            return self.rejected();
        }
        if (self.logging.pipelines.len == 1) {
            switch (self.beginOne(0, level, scope)) {
                .ready => |admission| {
                    frame.admission = admission;
                    return .{ .ready = .{ .route_mask = admission.route_mask, .config_generation = admission.config_generation, .frame = frame } };
                },
                .filtered => {},
                .sampled => frame.outcome = .{ .result = .sampled },
                .closed => frame.outcome = .{ .result = .rejected_closing },
            }
            Frames.depth -= 1;
            publish(frame);
            return switch (frame.outcome.result) {
                .sampled => .sampled,
                .rejected_closing => .closed,
                else => .filtered,
            };
        }
        const fanout = &Frames.fanouts[Frames.depth - 1];
        fanout.selected = 0;
        @memset(fanout.results[0..self.logging.pipelines.len], .{ .result = .filtered });
        frame.fanout = fanout;
        return self.beginMultiple(frame, level, scope);
    }
    // Keep the fanout loop out of ordinary single-output admission.
    noinline fn beginMultiple(self: *const Owner, frame: *Frame, level: core.Level, scope: []const u8) BeginResult {
        const fanout = frame.fanout.?;
        var sampled = false;
        var closed = false;
        for (self.logging.pipelines, 0..) |_, i| {
            const bit = @as(u64, 1) << @intCast(i);
            switch (self.beginOne(i, level, scope)) {
                .ready => |admission| {
                    fanout.admissions[i] = admission;
                    fanout.selected |= bit;
                },
                .filtered => {},
                .sampled => {
                    sampled = true;
                    fanout.results[i] = .{ .result = .sampled };
                },
                .closed => {
                    closed = true;
                    fanout.results[i] = .{ .result = .rejected_closing };
                },
            }
        }
        if (fanout.selected != 0) return .{ .ready = .{ .frame = frame } };
        Frames.depth -= 1;
        publish(frame);
        return if (closed) .closed else if (sampled) .sampled else .filtered;
    }
    pub fn endAdmission(self: *const Owner, admission: AdmissionType) void {
        const frame = admission.frame.?;
        if (frame.fanout) |fanout| {
            var i = self.logging.pipelines.len;
            while (i != 0) {
                i -= 1;
                if (fanout.selected & (@as(u64, 1) << @intCast(i)) != 0) self.endOne(i);
            }
        } else self.endOne(0);
        std.debug.assert(Frames.depth != 0 and frame == &Frames.stack[Frames.depth - 1]);
        Frames.depth -= 1;
        publish(frame);
    }
    pub fn nowNs(self: *const Owner) i64 {
        return self.logging.pipelines[0].runtime.nowNs();
    }
    fn submitOne(self: *const Owner, i: usize, admission: core.Admission, event: core.Event) !core.EmitResult {
        const binding = if (self.site) |site| site.bindings[i] else null;
        if (self.threadHandle(i)) |thread| return if (binding) |schema| thread.owner.submitWithSchema(admission, event, schema) else thread.owner.submit(admission, event);
        const runtime = self.logging.pipelines[i].runtime;
        return if (binding) |schema| runtime.submitWithSchema(admission, event, schema) else runtime.submit(admission, event);
    }
    pub fn submit(self: *const Owner, admission: AdmissionType, event: core.Event) !core.EmitResult {
        if (self.logging.pipelines.len == 1) {
            const i: usize = 0;
            const frame = admission.frame.?;
            const result = self.submitOne(i, frame.admission, event) catch |err| {
                frame.outcome = .{ .err = err };
                const pipeline = self.logging.pipelines[i];
                pipeline.runtime.reportError(err);
                if (pipeline.delivery == .required) return err;
                return .filtered;
            };
            frame.outcome = .{ .result = result };
            return result;
        }
        return self.submitMultiple(admission, event);
    }
    noinline fn submitMultiple(self: *const Owner, admission: AdmissionType, event: core.Event) !core.EmitResult {
        const fanout = admission.frame.?.fanout.?;
        var accepted = false;
        var aggregate: core.EmitResult = .filtered;
        var failure: ?anyerror = null;
        for (self.logging.pipelines, 0..) |pipeline, i| {
            if (fanout.selected & (@as(u64, 1) << @intCast(i)) == 0) continue;
            const result = self.submitOne(i, fanout.admissions[i], event) catch |err| {
                fanout.results[i] = .{ .err = err };
                pipeline.runtime.reportError(err);
                if (pipeline.delivery == .required and failure == null) failure = err;
                continue;
            };
            fanout.results[i] = .{ .result = result };
            if (result == .accepted) accepted = true else if (aggregate == .filtered) aggregate = result;
        }
        if (failure) |err| return err;
        return if (accepted) .accepted else aggregate;
    }
    pub fn captureFailed(self: *const Owner, err: anyerror) void {
        if (Frames.depth == 0) return;
        const frame = &Frames.stack[Frames.depth - 1];
        if (frame.fanout) |fanout| {
            for (self.logging.pipelines, 0..) |pipeline, i| if (fanout.selected & (@as(u64, 1) << @intCast(i)) != 0) {
                fanout.results[i] = .{ .err = err };
                pipeline.runtime.captureFailed(err);
            };
        } else {
            frame.outcome = .{ .err = err };
            self.logging.pipelines[0].runtime.captureFailed(err);
        }
    }
    pub fn reportError(self: *const Owner, err: anyerror) void {
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
        for (self.logging.pipelines) |pipeline| pipeline.runtime.reportError(err);
    }
    pub fn copyScope(self: *const Owner, destination: []u8) ![]const u8 {
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
    pub fn detach(self: *const Owner) !void {
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
