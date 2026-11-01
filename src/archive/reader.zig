//! Read-only inspection of live journals and append-only binary archives.
//! Every returned Event borrows independent copied storage until next() or
//! deinit(); neither journal locks nor reclamation cursors are ever touched.
const std = @import("std");
const journal_format = @import("../journal/format.zig");
const frame_format = @import("format.zig");
const compression = @import("compression.zig");
const codec = @import("../core/codec.zig");
const schema = @import("../journal/schema.zig");
const schema_codec = @import("../core/schema_codec.zig");
const field = @import("../core/field.zig");
const Field = field.Field;
const Event = @import("../core/event.zig").Event;

pub const Kind = enum { journal, archive, compressed_archive };
pub const Options = struct {
    /// Recovery exports only journal commits beyond its durable checkpoint.
    /// An archive has no acknowledgement cursor, so all complete frames apply.
    recover_only: bool = false,
    /// Includes copied payload, field scratch, journal scan bookkeeping, and
    /// complete fixed schema entries. No writable registry or mapping is used.
    max_memory_bytes: usize = 256 * 1024 * 1024,
    /// Headerless archives need an explicit payload bound. Storage is reserved
    /// once when opening, including follow mode, and reused for every record.
    max_archive_record_bytes: usize = 16 * 1024 * 1024,
    max_uncompressed_block_bytes: usize = compression.max_uncompressed_len,
    max_compressed_block_bytes: usize = compression.max_compressed_len,
};

const Candidate = struct { slot: usize, marker: u64 };
const SchemaState = struct {
    layout: schema.Layout,
    immutable_extension: [schema.extension_size]u8,
    /// Each complete entry has independent storage, including its fixed header.
    /// Decoded metadata borrows these copies rather than the live file.
    entries: []u8,
};
const JournalState = struct {
    version: u32,
    capacity: usize,
    max_record_bytes: usize,
    stride: usize,
    immutable_header: [64]u8,
    durable_sequence: u64,
    seen: []u64,
    candidates: []Candidate,
    schemas: ?SchemaState = null,
    candidate_count: usize = 0,
    candidate_cursor: usize = 0,
};
const ArchiveState = struct { offset: u64 = 0 };
const CompressedState = struct {
    offset: u64 = 0,
    block_offset: u64 = 0,
    compressed: []u8,
    raw: []u8,
    window: []u8,
    raw_length: usize = 0,
    raw_cursor: usize = 0,
    records_remaining: u32 = 0,
};

pub const Reader = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    options: Options,
    mode: union(Kind) { journal: JournalState, archive: ArchiveState, compressed_archive: CompressedState },
    payload: []u8,
    scratch: []Field,
    pending_format: bool = false,
    pending_compressed: ?CompressedState = null,
    /// Diagnostic position of the record most recently inspected.
    last_sequence: u64 = 0,
    last_offset: u64 = 0,

    pub fn open(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !*Reader {
        return openOptions(allocator, io, path, .{});
    }

    pub fn openOptions(allocator: std.mem.Allocator, io: std.Io, path: []const u8, options: Options) !*Reader {
        if (options.max_memory_bytes < @sizeOf(Reader)) return error.ReaderBudgetExceeded;
        const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only, .lock = .none });
        errdefer file.close(io);
        const stat = try file.stat(io);
        if (stat.kind != .file) return error.NotRegularFile;
        var magic: [8]u8 = undefined;
        const magic_len = try file.readPositionalAll(io, &magic, 0);
        const self = try allocator.create(Reader);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .file = file,
            .options = options,
            .mode = .{ .archive = .{} },
            .payload = &.{},
            .scratch = &.{},
        };
        errdefer allocator.free(self.payload);
        errdefer allocator.free(self.scratch);
        if (magic_len == 8 and std.mem.eql(u8, &magic, journal_format.magic)) {
            var header: [journal_format.header_bytes]u8 = undefined;
            try self.readExact(&header, 0, error.TruncatedJournal);
            const capacity = std.math.cast(usize, journal_format.get(u64, &header, 16)) orelse return error.CorruptHeader;
            const maximum = std.math.cast(usize, journal_format.get(u64, &header, 24)) orelse return error.CorruptHeader;
            const stride = std.math.cast(usize, journal_format.get(u64, &header, 32)) orelse return error.CorruptHeader;
            const layout = journal_format.layout(capacity, maximum) catch return error.CorruptHeader;
            if (stride != layout.stride) return error.LayoutMismatch;
            const file_version = journal_format.get(u32, &header, 8);
            const schema_layout: ?schema.Layout = switch (file_version) {
                journal_format.version => blk: {
                    try journal_format.validate(&header, capacity, maximum, stride);
                    break :blk null;
                },
                journal_format.schema_version => blk: {
                    try journal_format.validateV2(&header, capacity, maximum, stride);
                    break :blk try schema.readLayout(&header);
                },
                else => return error.UnsupportedVersion,
            };
            if (stat.size != if (schema_layout) |table| table.size else layout.size) return error.LayoutMismatch;
            if (journal_format.get(u64, &header, 64) > journal_format.max_sequence or journal_format.get(u64, &header, 72) > journal_format.max_sequence) return error.CorruptHeader;
            const checkpoint = try journal_format.checkpoint(&header);
            var bookkeeping = std.math.mul(usize, capacity, @sizeOf(u64) + @sizeOf(Candidate)) catch return error.ReaderBudgetExceeded;
            const schema_bytes = if (schema_layout) |table| std.math.mul(usize, table.capacity, table.stride) catch return error.ReaderBudgetExceeded else 0;
            bookkeeping = std.math.add(usize, bookkeeping, schema_bytes) catch return error.ReaderBudgetExceeded;
            try self.checkBudget(maximum, bookkeeping);
            const seen = try allocator.alloc(u64, capacity);
            errdefer allocator.free(seen);
            @memset(seen, 0);
            const candidates = try allocator.alloc(Candidate, capacity);
            errdefer allocator.free(candidates);
            const schema_entries: []u8 = if (schema_layout != null) try allocator.alloc(u8, schema_bytes) else &.{};
            errdefer if (schema_layout != null) allocator.free(schema_entries);
            try self.allocateScratch(maximum, bookkeeping);
            self.mode = .{ .journal = .{
                .version = file_version,
                .capacity = capacity,
                .max_record_bytes = maximum,
                .stride = stride,
                .immutable_header = header[0..64].*,
                .durable_sequence = checkpoint.sequence,
                .seen = seen,
                .candidates = candidates,
                .schemas = if (schema_layout) |table| .{
                    .layout = table,
                    .immutable_extension = header[schema.extension_offset..][0..schema.extension_size].*,
                    .entries = schema_entries,
                } else null,
            } };
        } else if (magic_len < magic.len and (std.mem.eql(u8, magic[0..magic_len], compression.magic[0..magic_len]) or std.mem.eql(u8, magic[0..magic_len], frame_format.magic[0..magic_len]))) {
            self.pending_format = true;
        } else if (magic_len == magic.len and std.mem.eql(u8, &magic, compression.magic)) {
            try self.allocateCompressed();
        } else if (magic_len != 0 and !std.mem.eql(u8, magic[0..magic_len], frame_format.magic[0..magic_len])) {
            if (magic_len < 8 and std.mem.eql(u8, magic[0..magic_len], journal_format.magic[0..magic_len])) return error.TruncatedJournal;
            return error.InvalidInputMagic;
        }
        if (self.mode == .archive) try self.allocateScratch(options.max_archive_record_bytes, 0);
        if (self.pending_format) self.pending_compressed = try self.compressedStorage();
        return self;
    }

    pub fn kind(self: *const Reader) Kind {
        return std.meta.activeTag(self.mode);
    }

    pub fn deinit(self: *Reader) void {
        self.file.close(self.io);
        const allocator = self.allocator;
        switch (self.mode) {
            .journal => |state| {
                allocator.free(state.seen);
                allocator.free(state.candidates);
                if (state.schemas) |table| allocator.free(table.entries);
            },
            .archive => {},
            .compressed_archive => |state| {
                self.freeCompressed(state);
            },
        }
        if (self.pending_compressed) |state| self.freeCompressed(state);
        allocator.free(self.payload);
        allocator.free(self.scratch);
        allocator.destroy(self);
    }

    /// Null means no unseen complete record currently exists; callers can
    /// call again after a delay. IncompleteFrame is retryable in archive follow
    /// mode, but a static export must report it as a damaged trailing record.
    pub fn next(self: *Reader) !?Event {
        if (self.pending_format and !try self.detectArchiveFormat()) return null;
        return switch (self.mode) {
            .journal => self.nextJournal(),
            .archive => self.nextArchive(),
            .compressed_archive => self.nextCompressed(),
        };
    }

    fn detectArchiveFormat(self: *Reader) !bool {
        var magic: [8]u8 = undefined;
        const length = try self.file.readPositionalAll(self.io, &magic, 0);
        if (length == 0) return false;
        if (length < magic.len) return error.IncompleteFrame;
        if (std.mem.eql(u8, &magic, compression.magic)) {
            self.mode = .{ .compressed_archive = self.pending_compressed.? };
            self.pending_compressed = null;
            self.allocator.free(self.payload);
            self.payload = &.{};
        } else if (std.mem.eql(u8, &magic, frame_format.magic)) {
            self.freeCompressed(self.pending_compressed.?);
            self.pending_compressed = null;
        } else return error.InvalidInputMagic;
        self.pending_format = false;
        return true;
    }

    fn nextJournal(self: *Reader) !?Event {
        const state = &self.mode.journal;
        self.last_offset = 0;
        self.last_sequence = 0;
        var progress: [80]u8 = undefined;
        try self.readExact(&progress, 0, error.TruncatedJournal);
        try self.validateJournalHeader(&progress);
        if (state.candidate_cursor == state.candidate_count) try self.scanJournal();
        while (state.candidate_cursor < state.candidate_count) {
            const candidate = state.candidates[state.candidate_cursor];
            const copied = try self.copyCommit(candidate);
            // A failed validation retains the candidate for the next attempt.
            state.candidate_cursor += 1;
            if (copied) |event| {
                state.seen[candidate.slot] = candidate.marker;
                // Apply recovery selection after checksum/codec validation,
                // so damage remains visible even in a checkpointed slot.
                if (self.options.recover_only and candidate.marker >> 2 <= state.durable_sequence) continue;
                return event;
            }
        }
        return null;
    }

    fn scanJournal(self: *Reader) !void {
        const state = &self.mode.journal;
        var header: [journal_format.header_bytes]u8 = undefined;
        try self.readExact(&header, 0, error.TruncatedJournal);
        try self.validateJournalHeader(&header);
        if (self.options.recover_only) {
            const checkpoint = try journal_format.checkpoint(&header);
            state.durable_sequence = @max(state.durable_sequence, checkpoint.sequence);
        }
        var count: usize = 0;
        for (0..state.capacity) |slot| {
            const offset = journal_format.header_bytes + slot * state.stride;
            self.last_offset = @intCast(offset);
            var first: [8]u8 = undefined;
            var second: [8]u8 = undefined;
            try self.readExact(&first, @intCast(offset), error.TruncatedJournal);
            const marker = journal_format.get(u64, &first, 0);
            if (marker == 0 or marker == state.seen[slot]) continue;
            try self.readExact(&second, @intCast(offset), error.TruncatedJournal);
            if (!std.mem.eql(u8, &first, &second)) continue;
            const sequence = marker >> 2;
            self.last_sequence = sequence;
            const status: journal_format.State = @enumFromInt(@as(u2, @truncate(marker)));
            if (sequence == 0 or (sequence - 1) % state.capacity != slot or status == .empty) return error.CorruptRecord;
            if (status != .committed) continue;
            state.candidates[count] = .{ .slot = slot, .marker = marker };
            count += 1;
        }
        std.mem.sort(Candidate, state.candidates[0..count], {}, struct {
            fn less(_: void, a: Candidate, b: Candidate) bool {
                return a.marker >> 2 < b.marker >> 2;
            }
        }.less);
        state.candidate_count = count;
        state.candidate_cursor = 0;
    }

    fn copyCommit(self: *Reader, candidate: Candidate) !?Event {
        const state = &self.mode.journal;
        const offset: u64 = @intCast(journal_format.header_bytes + candidate.slot * state.stride);
        self.last_offset = offset;
        self.last_sequence = candidate.marker >> 2;
        // A slot reused while copying is retried/omitted, never decoded from
        // mmap-backed storage. Sequence-tagged commits prevent an ABA match.
        for (0..3) |_| {
            var before: [journal_format.slot_header_bytes]u8 = undefined;
            var after: [journal_format.slot_header_bytes]u8 = undefined;
            try self.readExact(&before, offset, error.TruncatedJournal);
            if (journal_format.get(u64, &before, 0) != candidate.marker) return null;
            const sequence = journal_format.get(u64, &before, 8);
            const generation = journal_format.get(u64, &before, 16);
            const length: usize = journal_format.get(u32, &before, 24);
            const valid = sequence == candidate.marker >> 2 and sequence != 0 and
                (sequence - 1) % state.capacity == candidate.slot and generation == (sequence - 1) / state.capacity + 1 and length <= state.max_record_bytes;
            if (valid) try self.readExact(self.payload[0..length], offset + journal_format.slot_header_bytes, error.TruncatedJournal);
            try self.readExact(&after, offset, error.TruncatedJournal);
            if (!std.mem.eql(u8, &before, &after)) continue;
            if (!valid) return error.CorruptRecord;
            const payload = self.payload[0..length];
            const checksum = if (state.version == journal_format.version)
                journal_format.checksum(sequence, generation, payload)
            else
                journal_format.checksumV2(sequence, generation, before[32..56], payload);
            if (journal_format.get(u32, &before, 28) != checksum) return error.CorruptRecord;
            if (state.version == journal_format.schema_version) {
                const reference = try readReference(&before);
                if (reference) |ref| return try schema_codec.resolve(payload, try self.copySchema(ref), self.scratch);
            }
            return try codec.decode(payload, self.scratch);
        }
        return null;
    }

    fn nextArchive(self: *Reader) !?Event {
        const state = &self.mode.archive;
        const stat = try self.file.stat(self.io);
        self.last_offset = state.offset;
        self.last_sequence = 0;
        if (stat.size < state.offset) return error.ArchiveTruncated;
        if (stat.size == state.offset) return null;
        if (stat.size - state.offset < frame_format.header_size) return error.IncompleteFrame;
        var header: [frame_format.header_size]u8 = undefined;
        try self.readExact(&header, state.offset, error.IncompleteFrame);
        const frame = try frame_format.validate(&header);
        const frame_size: u64 = frame_format.header_size + @as(u64, frame.payload_len);
        if (frame.payload_len > self.payload.len) return error.ArchiveRecordTooLarge;
        if (stat.size - state.offset < frame_size) return error.IncompleteFrame;
        const payload = self.payload[0..frame.payload_len];
        try self.readExact(payload, state.offset + frame_format.header_size, error.IncompleteFrame);
        var after: [frame_format.header_size]u8 = undefined;
        try self.readExact(&after, state.offset, error.IncompleteFrame);
        if (!std.mem.eql(u8, &header, &after)) return error.FrameChanged;
        const event = try self.decodeArchivePayload(frame, payload);
        self.last_sequence = event.sequence;
        state.offset = std.math.add(u64, state.offset, frame_size) catch return error.InvalidLength;
        return event;
    }

    fn decodeArchivePayload(self: *Reader, frame: frame_format.Header, payload: []const u8) !Event {
        if (frame.payload_len > self.options.max_archive_record_bytes) return error.ArchiveRecordTooLarge;
        if (payload.len != frame.payload_len) return error.InvalidLength;
        if (frame.crc32 != frame_format.frameCRC(payload)) return error.CorruptRecord;
        return codec.decode(payload, self.scratch);
    }

    fn nextCompressed(self: *Reader) !?Event {
        const state = &self.mode.compressed_archive;
        self.last_sequence = 0;
        if (state.raw_cursor == state.raw_length) {
            if (state.records_remaining != 0) return error.RecordCountMismatch;
            if (!try self.readCompressedBlock()) return null;
        }
        self.last_offset = state.block_offset;
        const remaining = state.raw[state.raw_cursor..state.raw_length];
        if (remaining.len < frame_format.header_size) return error.InvalidFrame;
        const frame = try frame_format.validate(remaining[0..frame_format.header_size]);
        const size = frame_format.header_size + @as(usize, frame.payload_len);
        if (size > remaining.len or state.records_remaining == 0) return error.InvalidFrame;
        const event = try self.decodeArchivePayload(frame, remaining[frame_format.header_size..size]);
        state.raw_cursor += size;
        state.records_remaining -= 1;
        self.last_sequence = event.sequence;
        return event;
    }

    fn readCompressedBlock(self: *Reader) !bool {
        const state = &self.mode.compressed_archive;
        const stat = try self.file.stat(self.io);
        self.last_offset = state.offset;
        if (stat.size < state.offset) return error.ArchiveTruncated;
        if (stat.size == state.offset) return false;
        if (stat.size - state.offset < compression.header_size) return error.IncompleteFrame;
        var before: [compression.header_size]u8 = undefined;
        var after: [compression.header_size]u8 = undefined;
        try self.readExact(&before, state.offset, error.IncompleteFrame);
        const header = try compression.validate(&before);
        const total = compression.header_size + @as(usize, header.compressed_len);
        if (header.uncompressed_len > state.raw.len or total > state.compressed.len) return error.ArchiveBlockTooLarge;
        if (stat.size - state.offset < total) return error.IncompleteFrame;
        const block = state.compressed[0..total];
        try self.readExact(block, state.offset, error.IncompleteFrame);
        try self.readExact(&after, state.offset, error.IncompleteFrame);
        if (!std.mem.eql(u8, &before, &after) or !std.mem.eql(u8, block[0..compression.header_size], &before)) return error.FrameChanged;
        const decoded = try compression.decodeBlock(block, state.raw, state.window);
        state.block_offset = state.offset;
        state.offset += decoded.consumed;
        state.raw_length = decoded.raw.len;
        state.raw_cursor = 0;
        state.records_remaining = decoded.header.record_count;
        return true;
    }

    fn readExact(self: *Reader, destination: []u8, offset: u64, eof_error: anyerror) !void {
        if (try self.file.readPositionalAll(self.io, destination, offset) != destination.len) return eof_error;
    }

    fn validateJournalHeader(self: *Reader, header: []const u8) !void {
        const state = &self.mode.journal;
        if (!std.mem.eql(u8, header[0..64], &state.immutable_header)) return error.CorruptHeader;
        if (journal_format.get(u64, header, 64) > journal_format.max_sequence or journal_format.get(u64, header, 72) > journal_format.max_sequence) return error.CorruptHeader;
        if (state.schemas) |table| {
            var extension: [schema.extension_size]u8 = undefined;
            const current = if (header.len >= schema.extension_offset + schema.extension_size)
                header[schema.extension_offset..][0..schema.extension_size]
            else blk: {
                try self.readExact(&extension, schema.extension_offset, error.TruncatedSchema);
                break :blk &extension;
            };
            if (!std.mem.eql(u8, current, &table.immutable_extension)) return error.CorruptHeader;
        }
    }

    fn copySchema(self: *Reader, reference: schema.Ref) !schema.Definition {
        if (!schema.supportedVersion(reference.version)) return error.UnsupportedSchemaVersion;
        const table = if (self.mode.journal.schemas) |*value| value else return error.MissingSchema;
        if (reference.id == 0 or reference.id > table.layout.capacity) return error.MissingSchema;
        const index: usize = reference.id - 1;
        const relative = index * table.layout.stride;
        const offset: u64 = @intCast(table.layout.offset + relative);
        const copy = table.entries[relative..][0..table.layout.stride];
        // Definitions are append-only, but a live reservation may publish while
        // being copied. Require both complete headers and the copied header to
        // match before trusting its commit marker, length, checksum, or hash.
        for (0..3) |_| {
            var before: [schema.entry_header_size]u8 = undefined;
            var after: [schema.entry_header_size]u8 = undefined;
            try self.readExact(&before, offset, error.TruncatedSchema);
            try self.readExact(copy, offset, error.TruncatedSchema);
            try self.readExact(&after, offset, error.TruncatedSchema);
            if (!std.mem.eql(u8, &before, &after) or !std.mem.eql(u8, copy[0..schema.entry_header_size], &before)) continue;
            const definition = (try schema.decodeEntry(copy, index, table.layout.max_definition_bytes)) orelse return error.MissingSchema;
            if (definition.ref.id != reference.id or definition.ref.version != reference.version or !std.mem.eql(u8, &definition.ref.hash, &reference.hash)) return error.MissingSchema;
            return definition;
        }
        return error.SchemaChanged;
    }

    fn readReference(header: []const u8) !?schema.Ref {
        const id = journal_format.get(u32, header, 32);
        const reference_version = journal_format.get(u16, header, 36);
        if (journal_format.get(u16, header, 38) != 0) return error.InvalidSchemaReference;
        const hash: [16]u8 = header[40..56].*;
        if (id == 0) {
            if (reference_version != 0 or !std.mem.eql(u8, &hash, &([_]u8{0} ** 16))) return error.InvalidSchemaReference;
            return null;
        }
        return .{ .id = id, .version = reference_version, .hash = hash };
    }

    fn checkBudget(self: *Reader, bytes: usize, bookkeeping: usize) !void {
        // The event-wide node budget includes top-level fields/arguments. A
        // Field slot is large/aligned enough for either nested descriptor type.
        const count = codec.decode_scratch_fields;
        const field_bytes = std.math.mul(usize, count, @sizeOf(Field)) catch return error.ReaderBudgetExceeded;
        var total = std.math.add(usize, bytes, field_bytes) catch return error.ReaderBudgetExceeded;
        total = std.math.add(usize, total, bookkeeping) catch return error.ReaderBudgetExceeded;
        total = std.math.add(usize, total, @sizeOf(Reader)) catch return error.ReaderBudgetExceeded;
        if (total > self.options.max_memory_bytes) return error.ReaderBudgetExceeded;
    }

    fn allocateScratch(self: *Reader, bytes: usize, bookkeeping: usize) !void {
        if (bytes == 0 or bytes > std.math.maxInt(u32)) return error.InvalidReaderOptions;
        try self.checkBudget(bytes, bookkeeping);
        self.payload = try self.allocator.alloc(u8, bytes);
        const count = codec.decode_scratch_fields;
        self.scratch = try self.allocator.alloc(Field, count);
    }

    fn allocateCompressed(self: *Reader) !void {
        self.mode = .{ .compressed_archive = try self.compressedStorage() };
    }

    fn compressedStorage(self: *Reader) !CompressedState {
        const options = self.options;
        if (options.max_uncompressed_block_bytes < frame_format.header_size or options.max_uncompressed_block_bytes > compression.max_uncompressed_len or options.max_compressed_block_bytes < 6 or options.max_compressed_block_bytes > compression.max_compressed_len or options.max_archive_record_bytes == 0 or options.max_archive_record_bytes > std.math.maxInt(u32)) return error.InvalidReaderOptions;
        const compressed_size = compression.header_size + options.max_compressed_block_bytes;
        var bookkeeping = std.math.add(usize, compressed_size, options.max_uncompressed_block_bytes) catch return error.ReaderBudgetExceeded;
        bookkeeping = std.math.add(usize, bookkeeping, compression.window_bytes) catch return error.ReaderBudgetExceeded;
        bookkeeping = std.math.add(usize, bookkeeping, self.payload.len) catch return error.ReaderBudgetExceeded;
        try self.checkBudget(0, bookkeeping);
        const encoded = try self.allocator.alloc(u8, compressed_size);
        errdefer self.allocator.free(encoded);
        const raw = try self.allocator.alloc(u8, options.max_uncompressed_block_bytes);
        errdefer self.allocator.free(raw);
        const window = try self.allocator.alloc(u8, compression.window_bytes);
        errdefer self.allocator.free(window);
        if (self.scratch.len == 0) self.scratch = try self.allocator.alloc(Field, codec.decode_scratch_fields);
        return .{ .compressed = encoded, .raw = raw, .window = window };
    }

    fn freeCompressed(self: *Reader, state: CompressedState) void {
        self.allocator.free(state.compressed);
        self.allocator.free(state.raw);
        self.allocator.free(state.window);
    }
};
