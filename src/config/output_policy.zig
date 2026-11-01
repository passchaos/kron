//! Optional route policy; resources exist only for configured output behavior.
const std = @import("std");
const redact = @import("../pipeline/redact.zig");
const sampling = @import("../pipeline/sampler.zig");
const Level = @import("../core/level.zig").Level;

pub const Options = struct {
    redaction: []const redact.Rule = &.{},
    sampling: ?sampling.Config = null,
    sample_bypass: Level = .warn,
    max_encoded_record_bytes: ?usize = null,
};

pub const Policy = struct {
    redactor: ?*redact.Redactor = null,
    sampler: ?sampling.Sampler = null,
    sample_bypass: Level,
    max_encoded_record_bytes: ?usize,

    pub fn configured(options: Options) bool {
        return options.redaction.len != 0 or options.sampling != null or options.max_encoded_record_bytes != null;
    }

    pub fn ownedBytes(options: Options) usize {
        if (!configured(options)) return 0;
        return @sizeOf(Policy) + if (options.redaction.len != 0) @sizeOf(redact.Redactor) else @as(usize, 0);
    }

    pub fn validate(options: Options) !void {
        if (options.max_encoded_record_bytes == 0) return error.InvalidEncodedRecordBudget;
        _ = try redact.Redactor.init(options.redaction);
        if (options.sampling) |config| _ = try sampling.Sampler.init(config);
    }

    pub fn create(allocator: std.mem.Allocator, options: Options) !?*Policy {
        try validate(options);
        if (!configured(options)) return null;
        const self = try allocator.create(Policy);
        errdefer allocator.destroy(self);
        const redactor = if (options.redaction.len != 0) blk: {
            const result = try allocator.create(redact.Redactor);
            errdefer allocator.destroy(result);
            result.* = try redact.Redactor.init(options.redaction);
            break :blk result;
        } else null;
        errdefer if (redactor) |result| allocator.destroy(result);
        self.* = .{ .redactor = redactor, .sampler = if (options.sampling) |config| try sampling.Sampler.init(config) else null, .sample_bypass = options.sample_bypass, .max_encoded_record_bytes = options.max_encoded_record_bytes };
        return self;
    }

    pub fn destroy(self: *Policy, allocator: std.mem.Allocator) void {
        if (self.redactor) |redactor| allocator.destroy(redactor);
        allocator.destroy(self);
    }

    pub fn eql(self: *const Policy, other: *const Policy) bool {
        if (self.sample_bypass != other.sample_bypass or self.max_encoded_record_bytes != other.max_encoded_record_bytes or (self.sampler == null) != (other.sampler == null) or (self.redactor == null) != (other.redactor == null)) return false;
        if (self.sampler) |sampler| if (!std.meta.eql(sampler.config, other.sampler.?.config)) return false;
        if (self.redactor) |redactor| return redactor.eql(other.redactor.?);
        return true;
    }

    /// Sampling decisions are frozen in the record mask. Only output-affecting
    /// policy enters recovery identity; mutable sample counters never do.
    pub fn hashOutput(self: *const Policy, hash: *std.hash.Wyhash) void {
        if (self.redactor) |redactor| {
            hash.update("\x00KRONREDACT1");
            redactor.hash(hash);
        }
        if (self.max_encoded_record_bytes) |limit| {
            hash.update("\x00KRONOUTPUTLIMIT1");
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, limit, .little);
            hash.update(&bytes);
        }
    }
};
