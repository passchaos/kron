const std = @import("std");
const Sink = @import("interface.zig").Sink;
const compression = @import("../archive/compression.zig");

/// Single-owner, borrowed child sink. Each input is exactly one KRONARC1 frame.
/// flush publishes an independent zlib block and confirms the child's written
/// boundary. Failed output leaves the block intact for explicit retry; a child
/// that accepted a prefix can therefore observe identifiable duplicate frames.
/// A partial corrupt trailing block must be repaired/truncated by the storage
/// owner before appending a retry; this sink does not silently discard evidence.
pub const CompressedArchiveSink = struct {
    allocator: std.mem.Allocator,
    child: Sink,
    raw: []u8,
    encoded: []u8,
    workspace: compression.Workspace,
    recovery_identity: ?[]u8,
    max_records: u32,
    raw_len: usize = 0,
    record_count: u32 = 0,
    encoded_len: usize = 0,
    accepted_records: u64 = 0,
    written_records: u64 = 0,
    written_blocks: u64 = 0,
    written_raw_bytes: u64 = 0,
    written_compressed_bytes: u64 = 0,

    pub const Options = struct {
        sink: Sink,
        max_raw_bytes: usize = 64 * 1024,
        max_records: u32 = 256,
        /// Payload bytes, excluding the 32-byte compression header. null uses
        /// the conservative bound; smaller-than-bound budgets are rejected.
        max_compressed_bytes: ?usize = null,
    };

    pub fn create(allocator: std.mem.Allocator, options: Options) !*CompressedArchiveSink {
        const bound = try compression.compressedBound(options.max_raw_bytes);
        if (options.max_raw_bytes < 24 or options.max_records == 0 or options.max_records > options.max_raw_bytes / 24) return error.InvalidBufferBudget;
        const capacity = options.max_compressed_bytes orelse bound;
        if (capacity < bound or capacity > compression.max_compressed_len) return error.InvalidBufferBudget;
        const self = try allocator.create(CompressedArchiveSink);
        errdefer allocator.destroy(self);
        const raw = try allocator.alloc(u8, options.max_raw_bytes);
        errdefer allocator.free(raw);
        @memset(raw, 0);
        const encoded = try allocator.alloc(u8, compression.header_size + capacity);
        errdefer allocator.free(encoded);
        @memset(encoded, 0);
        var workspace = try compression.Workspace.init(allocator);
        errdefer workspace.deinit();
        const identity = if (options.sink.recovery_identity) |child_identity|
            try std.fmt.allocPrint(allocator, "kron-compressed-archive:v1:deflate-zlib:{s}", .{child_identity})
        else
            null;
        self.* = .{ .allocator = allocator, .child = options.sink, .raw = raw, .encoded = encoded, .workspace = workspace, .recovery_identity = identity, .max_records = options.max_records };
        return self;
    }

    /// Observe flush/sync errors explicitly before deinit. This attempts a final
    /// flush; a failed pending block is then discarded. The child owns copies
    /// accepted by writeRecord, as required when runtime output buffers reuse.
    pub fn deinit(self: *CompressedArchiveSink) void {
        self.flush() catch {};
        self.workspace.deinit();
        const allocator = self.allocator;
        allocator.free(self.raw);
        allocator.free(self.encoded);
        if (self.recovery_identity) |identity| allocator.free(identity);
        allocator.destroy(self);
    }

    pub fn sink(self: *CompressedArchiveSink) Sink {
        return .{ .context = self, .vtable = &vtable, .supports_durable = self.child.supports_durable, .recovery_identity = self.recovery_identity };
    }

    pub fn writeRecord(self: *CompressedArchiveSink, record: []const u8) !void {
        try compression.validateFrame(record);
        if (record.len > self.raw.len) return error.RecordTooLarge;
        // A failed flush freezes this encoded batch until it is retried.
        if (self.encoded_len != 0) try self.flush();
        if (self.record_count == self.max_records or record.len > self.raw.len - self.raw_len) try self.flush();
        @memcpy(self.raw[self.raw_len..][0..record.len], record);
        self.raw_len += record.len;
        self.record_count += 1;
        self.accepted_records += 1;
    }

    pub fn flush(self: *CompressedArchiveSink) !void {
        if (self.raw_len == 0) return self.child.flush();
        if (self.encoded_len == 0) {
            const payload = try self.workspace.compress(self.raw[0..self.raw_len], self.encoded[compression.header_size..]);
            const header = compression.headerBytes(.{ .uncompressed_len = @intCast(self.raw_len), .compressed_len = @intCast(payload.len), .crc32 = std.hash.Crc32.hash(self.raw[0..self.raw_len]), .record_count = self.record_count });
            @memcpy(self.encoded[0..compression.header_size], &header);
            self.encoded_len = compression.header_size + payload.len;
        }
        try self.child.writeRecord(self.encoded[0..self.encoded_len]);
        try self.child.flush();
        self.written_records += self.record_count;
        self.written_blocks += 1;
        self.written_raw_bytes += self.raw_len;
        self.written_compressed_bytes += self.encoded_len;
        self.raw_len = 0;
        self.record_count = 0;
        self.encoded_len = 0;
    }

    pub fn sync(self: *CompressedArchiveSink) !void {
        if (!self.child.supports_durable) return error.UnsupportedDurability;
        try self.flush();
        try self.child.sync();
    }

    fn write(context: *anyopaque, record: []const u8) anyerror!void {
        return (@as(*CompressedArchiveSink, @ptrCast(@alignCast(context)))).writeRecord(record);
    }
    fn flushErased(context: *anyopaque) anyerror!void {
        return (@as(*CompressedArchiveSink, @ptrCast(@alignCast(context)))).flush();
    }
    fn syncErased(context: *anyopaque) anyerror!void {
        return (@as(*CompressedArchiveSink, @ptrCast(@alignCast(context)))).sync();
    }
    const vtable: Sink.VTable = .{ .writeRecord = write, .flush = flushErased, .sync = syncErased };
};
