//! Bounded Linux mmap MPSC journal; one consumer owns peek/release. Payloads
//! are opaque, self-contained codec bytes. Reservation and Record are borrowed
//! handles and must not be copied, used twice, or retained after release/deinit.
//! No allocator or syscall occurs on reserve/commit/abort/written release.
const std = @import("std");
const Storage = @import("storage.zig").Storage;
const format = @import("format.zig");
const schema_format = @import("schema.zig");
const Atomic = std.atomic.Value;
pub const SchemaRef = schema_format.Ref;
pub const SchemaDefinition = schema_format.Definition;

var next_thread_cookie: Atomic(u64) = .init(1);
threadlocal var thread_cookie: u64 = 0;

/// Read-only thread identity. Zero means this thread has never attached to a
/// single-producer channel. Ownership validation must not register strangers.
pub fn currentThreadCookie() u64 {
    return thread_cookie;
}

/// Explicit attachment cold path. Repeated calls on the same thread reuse its
/// cookie; the global atomic is touched only once during that thread's lifetime.
/// Saturation prevents a wrap from assigning an earlier cookie again.
pub fn registerCurrentThreadCookie() !u64 {
    if (thread_cookie != 0) return thread_cookie;
    var next = next_thread_cookie.load(.monotonic);
    while (next != std.math.maxInt(u64)) {
        if (next_thread_cookie.cmpxchgWeak(next, next + 1, .monotonic, .monotonic)) |current| {
            next = current;
            continue;
        }
        thread_cookie = next;
        return next;
    }
    return error.ThreadCookieExhausted;
}

pub const Options = struct {
    path: []const u8,
    capacity: usize,
    max_record_bytes: usize,
    recover: bool = true,
    schema_capacity: usize = 0,
    max_schema_bytes: usize = 8192,
    /// Volatile-memory-only opt-out. Mapped/recoverable journals reject it.
    verify_crc: bool = true,
};
pub const ReclaimBoundary = enum { written, durable };
pub const ProducerMode = enum { shared, single };

/// Process-local ownership; never persisted. A retired channel keeps all its
/// mapped data alive while the collector drains it or a new owner attaches.
pub const SingleProducerControl = struct {
    owner_id: Atomic(std.Thread.Id),
    owner_cookie: Atomic(u64),
    // Low bits: 0 active, 1 retired, 2 changing owner. Upper bits generation.
    state: Atomic(u64),
    in_flight: Atomic(usize) = .init(0),
    reserved_total: Atomic(u64) align(64) = .init(0),
    released_total: Atomic(u64) align(64) = .init(0),
    consumer_written: Atomic(u64) align(64) = .init(0),
    consumer_free_position: Atomic(u64) align(64) = .init(0),
    cached_producer_limit: u64 align(64) = 0,
    /// Process-local runtime space notification. One SPSC producer may wait;
    /// every epoch change precedes its conditional futex wake. It is separate
    /// from mapped written/free watermarks and never certifies record output.
    space_epoch: Atomic(u32) align(64) = .init(0),
    space_waiting: Atomic(bool) = .init(false),

    pub fn owner(self: *const SingleProducerControl) std.Thread.Id {
        return self.owner_id.load(.acquire);
    }
    pub fn ownerCookie(self: *const SingleProducerControl) u64 {
        return self.owner_cookie.load(.acquire);
    }
    pub fn generation(self: *const SingleProducerControl) u64 {
        return self.state.load(.acquire) >> 2;
    }
    pub fn retired(self: *const SingleProducerControl) bool {
        return self.state.load(.acquire) & 3 != 0;
    }
};

pub const SingleProducerToken = struct {
    journal: *Journal,
    generation: u64,
};

pub const Record = struct {
    sequence: u64,
    generation: u64,
    payload: []const u8,
    slot: usize,
    schema_ref: ?SchemaRef = null,
};

pub const Reservation = struct {
    journal: *Journal,
    sequence: u64,
    slot: usize,
    completed: bool = false,
    producer_generation: u64 = 0,
    schema_ref: ?SchemaRef = null,

    pub fn buffer(self: *const Reservation) []u8 {
        std.debug.assert(!self.completed);
        return self.journal.slotBytes(self.slot)[format.slot_header_bytes..][0..self.journal.max_record_bytes];
    }

    /// Publish only after the complete bytes/length/checksum have been written.
    /// Oversize errors leave the reservation live so the caller can abort it.
    pub fn commit(self: *Reservation, length: usize) !void {
        if (self.completed) return error.InvalidReservation;
        if (self.producer_generation != 0) try self.journal.validateSingleProducer(.{ .journal = self.journal, .generation = self.producer_generation });
        if (self.schema_ref) |reference| try self.journal.validateSchemaReady(reference);
        if (length > self.journal.max_record_bytes) return error.RecordTooLarge;
        const state = self.journal.slotState(self.slot);
        if (state.load(.acquire) != format.tag(self.sequence, .reserved)) return error.InvalidReservation;
        const bytes = self.journal.slotBytes(self.slot);
        const generation = self.journal.generation(self.sequence);
        self.journal.writeSlotSchema(bytes, self.schema_ref);
        format.put(u32, bytes, 24, @intCast(length));
        const checksum: u32 = if (!self.journal.verify_crc)
            0
        else if (self.journal.file_version == format.schema_version)
            format.checksumV3Slot(bytes, length)
        else
            self.journal.slotChecksum(self.sequence, generation, bytes, self.buffer()[0..length]);
        format.put(u32, bytes, 28, checksum);
        state.store(format.tag(self.sequence, .committed), .release);
        if (self.producer_generation != 0) self.journal.completeSingleReservation();
        self.completed = true;
    }

    /// A tombstone preserves normal reservation ordering and releases no slot
    /// until the consumer passes it. Abort is harmless after completion.
    pub fn abort(self: *Reservation) void {
        if (self.completed) return;
        if (self.producer_generation != 0) self.journal.validateSingleProducer(.{ .journal = self.journal, .generation = self.producer_generation }) catch return;
        if (self.journal.slotState(self.slot).cmpxchgStrong(format.tag(self.sequence, .reserved), format.tag(self.sequence, .aborted), .release, .monotonic) == null and self.producer_generation != 0) self.journal.completeSingleReservation();
        self.completed = true;
    }
};

pub const Journal = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mapping: Storage,
    capacity: usize,
    max_record_bytes: usize,
    stride: usize,
    file_version: u32,
    verify_crc: bool,
    schema: ?schema_format.Registry,
    producer_mode: ProducerMode,
    single: SingleProducerControl,
    // The mapped tail is authoritative across process exits. Per-slot turns
    // prevent a producer paused immediately after claiming tail from being
    // overtaken and overwritten after the ring wraps.
    turns: []Atomic(u64),
    recovery_order: []usize,
    recovery_length: usize = 0,
    recovery_cursor: usize = 0,
    recovery_tail: u64 = 0,
    head: u64,
    occupied: Atomic(usize),
    high_water: Atomic(usize),
    checkpoint_epoch: u64,
    durable_reclaimed: Atomic(u64),
    sync_mutex: std.Io.Mutex = .init,
    schema_mutex: std.Io.Mutex = .init,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Journal {
        return createWithMode(allocator, io, options, .shared, false);
    }

    /// Exclusivity is fixed before publishing the Journal. MPSC reserve is
    /// permanently disabled on this instance; token lifecycle changes owners.
    pub fn createSingleProducer(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Journal {
        return createWithMode(allocator, io, options, .single, false);
    }

    pub fn createMemory(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Journal {
        return createWithMode(allocator, io, options, .shared, true);
    }

    pub fn createMemorySingleProducer(allocator: std.mem.Allocator, io: std.Io, options: Options) !*Journal {
        return createWithMode(allocator, io, options, .single, true);
    }

    pub fn isPersistent(self: *const Journal) bool {
        return self.mapping.isPersistent();
    }

    fn createWithMode(allocator: std.mem.Allocator, io: std.Io, options: Options, mode: ProducerMode, memory: bool) !*Journal {
        if (@import("builtin").cpu.arch.endian() != .little or @sizeOf(usize) != 8) return error.UnsupportedPlatform;
        if (!options.verify_crc and !memory) return error.CrcRequiredForRecovery;
        const layout = try format.layout(options.capacity, options.max_record_bytes);
        var schema_layout: ?schema_format.Layout = if (options.schema_capacity == 0) null else try schema_format.layout(layout.size, options.schema_capacity, options.max_schema_bytes);
        const file_size = if (schema_layout) |table| table.size else layout.size;
        var mapping = if (memory) try Storage.createMemory(allocator, file_size) else try Storage.openFile(io, options.path, file_size);
        errdefer mapping.deinit();
        if (mapping.fresh) {
            var identity: [16]u8 = undefined;
            try io.randomSecure(&identity);
            const zeroed = mapping.freshIsZeroed();
            if (schema_layout) |*table| {
                table.identity = identity;
                if (zeroed)
                    format.initializeV3Zeroed(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride, identity)
                else
                    format.initializeV3(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride, identity);
                schema_format.writeExtension(mapping.bytes[0..format.header_bytes], table.*, identity);
            } else if (zeroed)
                format.initializeZeroed(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride, identity)
            else
                format.initialize(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride, identity);
            // File length/header must reach the file before use. Directory
            // durability is included where the platform supports it.
            try mapping.publish();
        } else if (schema_layout) |*table| {
            const header_version = format.get(u32, mapping.bytes, 8);
            if (header_version == format.schema_version)
                try format.validateV3(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride)
            else if (header_version == format.schema_version_v2)
                try format.validateV2(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride)
            else
                return error.UnsupportedVersion;
            const actual = try schema_format.readLayout(mapping.bytes[0..format.header_bytes]);
            var expected = table.*;
            expected.identity = actual.identity;
            if (!std.meta.eql(actual, expected)) return error.LayoutMismatch;
            if (!std.mem.eql(u8, &actual.identity, mapping.bytes[40..56])) return error.CorruptSchema;
            table.* = actual;
        } else try format.validate(mapping.bytes, options.capacity, options.max_record_bytes, layout.stride);
        var registry: ?schema_format.Registry = null;
        errdefer if (registry) |*table| table.deinit();
        if (schema_layout) |table| {
            registry = try schema_format.Registry.init(allocator, io, @alignCast(mapping.bytes[table.offset..table.size]), table);
            // A complete descriptor may come from a previous failed sync.
            // Persist validated definitions before publishing process-local
            // ready flags, including when reopening an existing journal.
            if (!mapping.fresh) try mapping.publish();
            try registry.?.markRecoveredReady();
        }
        const checkpoint = try format.checkpoint(mapping.bytes);
        const self = try allocator.create(Journal);
        errdefer allocator.destroy(self);
        const turns = try allocator.alloc(Atomic(u64), options.capacity);
        errdefer allocator.free(turns);
        const recovery_order = try allocator.alloc(usize, options.capacity);
        errdefer allocator.free(recovery_order);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .mapping = mapping,
            .capacity = options.capacity,
            .max_record_bytes = options.max_record_bytes,
            .stride = layout.stride,
            .file_version = format.get(u32, mapping.bytes, 8),
            .verify_crc = options.verify_crc,
            .schema = registry,
            .producer_mode = mode,
            .single = .{
                .owner_id = .init(if (mode == .single) std.Thread.getCurrentId() else 0),
                .owner_cookie = .init(if (mode == .single) try registerCurrentThreadCookie() else 0),
                .state = .init(4),
            },
            .turns = turns,
            .recovery_order = recovery_order,
            .head = 0,
            .occupied = Atomic(usize).init(0),
            .high_water = Atomic(usize).init(0),
            .checkpoint_epoch = checkpoint.epoch,
            .durable_reclaimed = Atomic(u64).init(checkpoint.sequence),
        };
        try self.scanRecovery(options.recover);
        if (mode == .single) {
            self.single.reserved_total.store(self.recovery_length, .monotonic);
            const first_position = if (self.recovery_length == 0) self.head else format.get(u64, self.slotBytes(self.recovery_order[0]), 8) - 1;
            self.single.consumer_free_position.store(first_position, .monotonic);
            self.single.consumer_written.store(self.written().load(.monotonic), .monotonic);
            self.single.cached_producer_limit = first_position + self.capacity;
        }
        return self;
    }

    fn tail(self: *const Journal) *Atomic(u64) {
        return @ptrCast(@alignCast(self.mapping.bytes[64..].ptr));
    }
    fn written(self: *const Journal) *Atomic(u64) {
        return @ptrCast(@alignCast(self.mapping.bytes[72..].ptr));
    }
    fn slotBytes(self: *const Journal, index: usize) []u8 {
        return self.mapping.bytes[format.header_bytes + index * self.stride ..][0..self.stride];
    }
    fn slotState(self: *const Journal, index: usize) *Atomic(u64) {
        return @ptrCast(@alignCast(self.slotBytes(index).ptr));
    }
    fn generation(self: *const Journal, sequence: u64) u64 {
        return (sequence - 1) / self.capacity + 1;
    }

    fn writeSlotSchema(self: *const Journal, bytes: []u8, reference: ?SchemaRef) void {
        if (self.file_version == format.version) return;
        @memset(bytes[32..56], 0);
        if (reference) |ref| {
            format.put(u32, bytes, 32, ref.id);
            format.put(u16, bytes, 36, ref.version);
            @memcpy(bytes[40..56], &ref.hash);
        }
    }

    fn readSlotSchema(self: *const Journal, bytes: []const u8) !?SchemaRef {
        if (self.file_version == format.version) return null;
        const id = format.get(u32, bytes, 32);
        const reference_version = format.get(u16, bytes, 36);
        if (format.get(u16, bytes, 38) != 0) return error.InvalidSchemaReference;
        const hash: [16]u8 = bytes[40..56].*;
        if (id == 0) {
            if (reference_version != 0 or !std.mem.eql(u8, &hash, &([_]u8{0} ** 16))) return error.InvalidSchemaReference;
            return null;
        }
        return .{ .id = id, .version = reference_version, .hash = hash };
    }

    fn slotChecksum(self: *const Journal, sequence: u64, generation_value: u64, bytes: []const u8, payload: []const u8) u32 {
        return if (self.file_version == format.version) format.checksum(sequence, generation_value, payload) else format.checksumV2(sequence, generation_value, bytes[32..56], payload);
    }

    fn validateSchemaReady(self: *Journal, reference: SchemaRef) !void {
        if (self.schema) |*registry| return registry.validateReady(reference);
        return error.SchemasDisabled;
    }
    fn nextTurn(self: *const Journal, position: u64, index: usize) u64 {
        const base = position - position % self.capacity;
        const candidate = base + index;
        return if (candidate < position) candidate + self.capacity else candidate;
    }

    fn validateSlot(self: *Journal, index: usize, marker: u64) !Record {
        const bytes = self.slotBytes(index);
        const sequence = format.get(u64, bytes, 8);
        const gen = format.get(u64, bytes, 16);
        const length = format.get(u32, bytes, 24);
        if (sequence == 0 or sequence > format.max_sequence or marker != format.tag(sequence, .committed)) return error.CorruptRecord;
        if ((sequence - 1) % self.capacity != index or gen != self.generation(sequence) or length > self.max_record_bytes) return error.CorruptRecord;
        const payload = bytes[format.slot_header_bytes..][0..length];
        if (self.verify_crc and format.get(u32, bytes, 28) !=
            (if (self.file_version == format.schema_version)
                format.checksumV3Slot(bytes, length)
            else
                self.slotChecksum(sequence, gen, bytes, payload))) return error.CorruptRecord;
        const reference = try self.readSlotSchema(bytes);
        if (reference) |ref| try self.validateSchemaReady(ref);
        return .{ .sequence = sequence, .generation = gen, .payload = payload, .slot = index, .schema_ref = reference };
    }

    fn scanRecovery(self: *Journal, recover: bool) !void {
        var position = self.tail().load(.acquire);
        const durable_reclaimed = self.durable_reclaimed.load(.monotonic);
        if (position > format.max_sequence) return error.CorruptHeader;
        position = @max(position, durable_reclaimed);
        // First pass is read-only: errors retain every slot as diagnostic evidence.
        for (0..self.capacity) |index| {
            const marker = self.slotState(index).load(.acquire);
            if (marker == 0) continue;
            const state: format.State = @enumFromInt(@as(u2, @truncate(marker)));
            const sequence = marker >> 2;
            if (state == .empty or sequence == 0 or (sequence - 1) % self.capacity != index) return error.CorruptRecord;
            position = @max(position, sequence);
            if (state != .committed) continue;
            const record = try self.validateSlot(index, marker);
            if (record.sequence <= durable_reclaimed) continue;
            if (!recover) return error.RecoveryRequired;
            self.recovery_order[self.recovery_length] = index;
            self.recovery_length += 1;
        }
        // A ring can have at most capacity outstanding reservations. This also
        // rejects corrupted cursors instead of making pending records unreachable.
        for (self.recovery_order[0..self.recovery_length]) |index| {
            const sequence = format.get(u64, self.slotBytes(index), 8);
            if (position - sequence >= self.capacity) return error.CorruptHeader;
        }
        std.mem.sort(usize, self.recovery_order[0..self.recovery_length], self, struct {
            fn less(journal: *Journal, a: usize, b: usize) bool {
                return format.get(u64, journal.slotBytes(a), 8) < format.get(u64, journal.slotBytes(b), 8);
            }
        }.less);
        for (0..self.capacity) |index| {
            const marker = self.slotState(index).load(.acquire);
            const keep = marker != 0 and @as(u2, @truncate(marker)) == @intFromEnum(format.State.committed) and (marker >> 2) > durable_reclaimed;
            if (keep) {
                self.turns[index] = Atomic(u64).init((marker >> 2) - 1);
            } else {
                self.slotState(index).store(0, .release);
                self.turns[index] = Atomic(u64).init(self.nextTurn(position, index));
            }
        }
        self.tail().store(position, .release);
        self.recovery_tail = position;
        self.head = position;
        // A mapped written cursor can be ahead of records that still need
        // replay after a system crash. Rebuild completion from validated slots,
        // including abandoned reservations, rather than trusting that cursor.
        const completed_prefix = if (self.recovery_length == 0) position else format.get(u64, self.slotBytes(self.recovery_order[0]), 8) - 1;
        self.written().store(completed_prefix, .release);
        self.occupied.store(self.recovery_length, .monotonic);
        self.high_water.store(self.recovery_length, .monotonic);
    }

    /// Nonblocking bounded reservation. Full may occur behind an outstanding
    /// reservation; runtime owns blocking/wakeup and overflow policy.
    pub fn reserve(self: *Journal) !Reservation {
        if (self.producer_mode != .shared) return error.ExclusiveProducer;
        var position = self.tail().load(.monotonic);
        while (true) {
            if (position >= format.max_sequence) return error.SequenceExhausted;
            const index: usize = @intCast(position % self.capacity);
            const turn = self.turns[index].load(.acquire);
            if (turn < position) {
                const current = self.tail().load(.monotonic);
                if (current != position) {
                    position = current;
                    continue;
                }
                return error.Full;
            }
            if (turn > position) {
                position = self.tail().load(.monotonic);
                continue;
            }
            if (self.tail().cmpxchgWeak(position, position + 1, .monotonic, .monotonic)) |current| {
                position = current;
                continue;
            }
            const count_now = self.occupied.fetchAdd(1, .monotonic) + 1;
            // The peak only increases after publication. An observed peak
            // already covering this count needs no contended RMW; a stale
            // lower observation uses the CAS failure value to preserve concurrent maxima.
            var peak = self.high_water.load(.monotonic);
            while (count_now > peak) {
                if (self.high_water.cmpxchgWeak(peak, count_now, .monotonic, .monotonic)) |current| {
                    peak = current;
                } else break;
            }
            const sequence = position + 1;
            const bytes = self.slotBytes(index);
            // Slots remain unavailable through their in-memory turn even if the
            // process is paused before publishing this reservation marker.
            self.slotState(index).store(format.tag(sequence, .reserved), .release);
            format.put(u64, bytes, 8, sequence);
            format.put(u64, bytes, 16, self.generation(sequence));
            self.writeSlotSchema(bytes, null);
            return .{ .journal = self, .sequence = sequence, .slot = index };
        }
    }

    /// Cold schema registration serializes writers and persists the complete
    /// definition before ready publication. Failed sync retains the descriptor
    /// and leaves it unavailable to event producers until a successful retry.
    pub fn registerSchema(self: *Journal, metadata: schema_format.EventMeta) !SchemaRef {
        self.schema_mutex.lockUncancelable(self.io);
        defer self.schema_mutex.unlock(self.io);
        const registry = if (self.schema) |*table| table else return error.SchemasDisabled;
        const result = try registry.register(metadata);
        if (result.requires_sync) {
            self.sync_mutex.lockUncancelable(self.io);
            defer self.sync_mutex.unlock(self.io);
            try self.mapping.publish();
            try registry.markReady(result.ref);
        } else try registry.validateReady(result.ref);
        return result.ref;
    }

    pub fn resolveSchema(self: *Journal, reference: SchemaRef) !SchemaDefinition {
        if (self.schema) |*registry| return registry.resolve(reference);
        return error.SchemasDisabled;
    }

    /// Hot lookup of already-ready metadata. The journal owner must preserve
    /// schema definitions as immutable for the lifetime of borrowed views.
    /// Ready/marker/id/version/hash checks remain; body CRC/SHA/parse are owned
    /// by initialization/recovery and the strict resolveSchema/Reader paths.
    pub fn resolveReadySchema(self: *Journal, reference: SchemaRef) !SchemaDefinition {
        if (self.schema) |*registry| return registry.resolveReady(reference);
        return error.SchemasDisabled;
    }

    pub fn getSchemaLayout(self: *const Journal) ?schema_format.Layout {
        if (self.schema) |*registry| return registry.spec;
        return null;
    }

    /// Ready lookup is bounded and performs no allocation or syscall.
    pub fn reserveWithSchema(self: *Journal, reference: SchemaRef) !Reservation {
        try self.validateSchemaReady(reference);
        var reservation = try self.reserve();
        reservation.schema_ref = reference;
        self.writeSlotSchema(self.slotBytes(reservation.slot), reference);
        return reservation;
    }

    pub fn singleProducerControl(self: *Journal) !*const SingleProducerControl {
        if (self.producer_mode != .single) return error.WrongProducerMode;
        return &self.single;
    }

    pub fn singleProducerToken(self: *Journal) !SingleProducerToken {
        if (self.producer_mode != .single) return error.WrongProducerMode;
        const token: SingleProducerToken = .{ .journal = self, .generation = self.single.generation() };
        try self.validateSingleProducer(token);
        return token;
    }

    fn validateSingleProducer(self: *Journal, token: SingleProducerToken) !void {
        if (self.producer_mode != .single) return error.WrongProducerMode;
        if (token.journal != self) return error.InvalidToken;
        const state = self.single.state.load(.acquire);
        if (token.generation != state >> 2) return error.StaleToken;
        if (state & 3 != 0) return error.Retired;
        const cookie = currentThreadCookie();
        if (cookie == 0 or self.single.owner_cookie.load(.monotonic) != cookie) return error.WrongThread;
        if (self.single.owner_id.load(.monotonic) != std.Thread.getCurrentId()) return error.WrongThread;
    }

    /// One owner thread only. Common reserves use the cached consumer limit;
    /// acquire refresh occurs when it is exhausted. Recovery gaps use per-slot
    /// turn validation until contiguous consumer progress catches up. No CAS
    /// or read-modify-write occurs on the successful SPSC reserve path.
    pub fn reserveSingleProducer(self: *Journal, token: SingleProducerToken) !Reservation {
        try self.validateSingleProducer(token);
        const position = self.tail().load(.monotonic);
        if (position >= format.max_sequence) return error.SequenceExhausted;
        const index: usize = @intCast(position % self.capacity);
        if (position >= self.single.cached_producer_limit) {
            self.single.cached_producer_limit = self.single.consumer_free_position.load(.acquire) + self.capacity;
            if (position >= self.single.cached_producer_limit and self.turns[index].load(.acquire) != position) return error.Full;
        }
        self.tail().store(position + 1, .release);
        const released = self.single.released_total.load(.acquire);
        const reserved = self.single.reserved_total.load(.monotonic) + 1;
        self.single.reserved_total.store(reserved, .release);
        const count_now: usize = @intCast(reserved - released);
        if (count_now > self.high_water.load(.monotonic)) self.high_water.store(count_now, .monotonic);
        self.single.in_flight.store(self.single.in_flight.load(.monotonic) + 1, .monotonic);
        const sequence = position + 1;
        const bytes = self.slotBytes(index);
        self.slotState(index).store(format.tag(sequence, .reserved), .release);
        format.put(u64, bytes, 8, sequence);
        format.put(u64, bytes, 16, self.generation(sequence));
        self.writeSlotSchema(bytes, null);
        return .{ .journal = self, .sequence = sequence, .slot = index, .producer_generation = token.generation };
    }

    pub fn reserveSingleProducerWithSchema(self: *Journal, token: SingleProducerToken, reference: SchemaRef) !Reservation {
        try self.validateSchemaReady(reference);
        var reservation = try self.reserveSingleProducer(token);
        reservation.schema_ref = reference;
        self.writeSlotSchema(self.slotBytes(reservation.slot), reference);
        return reservation;
    }

    fn completeSingleReservation(self: *Journal) void {
        const count_now = self.single.in_flight.load(.monotonic);
        std.debug.assert(count_now != 0);
        self.single.in_flight.store(count_now - 1, .monotonic);
    }

    /// The owner must finish/abort outstanding reservations before retiring.
    /// Committed records stay available to the consumer after retirement.
    pub fn retireSingleProducer(self: *Journal, token: SingleProducerToken) !void {
        try self.validateSingleProducer(token);
        if (self.single.in_flight.load(.monotonic) != 0) return error.OutstandingReservation;
        self.single.state.store((token.generation << 2) | 1, .release);
    }

    /// Claim a retired channel for the current thread. Lifecycle CAS only;
    /// reserve remains single-writer load/store. Old tokens become stale.
    pub fn reactivateSingleProducer(self: *Journal) !SingleProducerToken {
        if (self.producer_mode != .single) return error.WrongProducerMode;
        const old_state = self.single.state.load(.acquire);
        if (old_state & 3 != 1) return error.AlreadyActive;
        const new_generation = (old_state >> 2) + 1;
        if (new_generation > format.max_sequence) return error.GenerationExhausted;
        const cookie = try registerCurrentThreadCookie();
        if (self.single.state.cmpxchgStrong(old_state, (new_generation << 2) | 2, .acquire, .monotonic) != null) return error.AlreadyActive;
        self.single.owner_id.store(std.Thread.getCurrentId(), .monotonic);
        self.single.owner_cookie.store(cookie, .monotonic);
        self.single.cached_producer_limit = self.single.consumer_free_position.load(.acquire) + self.capacity;
        self.single.state.store(new_generation << 2, .release);
        return .{ .journal = self, .generation = new_generation };
    }

    /// Recovered records are served in sorted order before new live records.
    /// In live mode an uncommitted reservation always blocks later records.
    pub fn peek(self: *Journal) ?Record {
        if (self.recovery_cursor < self.recovery_length) {
            const index = self.recovery_order[self.recovery_cursor];
            return self.liveRecord(index);
        }
        while (self.head < self.tail().load(.acquire)) {
            const sequence = self.head + 1;
            const index: usize = @intCast(self.head % self.capacity);
            const marker = self.slotState(index).load(.acquire);
            if (marker == format.tag(sequence, .committed)) return self.liveRecord(index);
            if (marker != format.tag(sequence, .aborted)) return null;
            self.reclaim(index, sequence);
            self.head += 1;
        }
        return null;
    }

    /// Enumerate this opening's remaining recovered records without advancing
    /// cursor/head or reclaiming slots. Index is relative to recovery_cursor.
    /// Runtime initialization uses this before its worker starts; otherwise
    /// the single consumer must exclude concurrent release/iteration. Returned
    /// payloads borrow the mapping until their record is released or deinit.
    pub fn recoveryRecordAt(self: *Journal, index: usize) !?Record {
        if (index >= self.recovery_length - self.recovery_cursor) return null;
        const slot = self.recovery_order[self.recovery_cursor + index];
        return try self.validateSlot(slot, self.slotState(slot).load(.acquire));
    }

    /// Validates length, generation and checksum before exposing borrowed
    /// payloads. Damage returns an error without reclaiming the damaged slot.
    pub fn peekChecked(self: *Journal) !?Record {
        if (self.recovery_cursor < self.recovery_length) {
            const index = self.recovery_order[self.recovery_cursor];
            return try self.validateSlot(index, self.slotState(index).load(.acquire));
        }
        while (self.head < self.tail().load(.acquire)) {
            const sequence = self.head + 1;
            const index: usize = @intCast(self.head % self.capacity);
            const marker = self.slotState(index).load(.acquire);
            if (marker == format.tag(sequence, .committed)) return try self.validateSlot(index, marker);
            if (marker == 0 or marker == format.tag(sequence, .reserved)) return null;
            if (marker != format.tag(sequence, .aborted)) return error.CorruptRecord;
            self.reclaim(index, sequence);
            self.head += 1;
        }
        return null;
    }

    /// Borrows a consecutive batch without reclaiming any record. Leading
    /// tombstones are consumed; an internal tombstone/reservation ends the
    /// batch. Flush all required outputs before releasing records in order.
    /// A batch ends at the recovered/live boundary.
    pub fn peekBatch(self: *Journal, destination: []Record) []Record {
        if (destination.len == 0) return destination[0..0];
        destination[0] = self.peek() orelse return destination[0..0];
        var length: usize = 1;
        if (self.recovery_cursor < self.recovery_length) {
            while (length < destination.len and self.recovery_cursor + length < self.recovery_length) : (length += 1) {
                destination[length] = self.liveRecord(self.recovery_order[self.recovery_cursor + length]);
            }
        } else {
            const target = self.tail().load(.acquire);
            while (length < destination.len and self.head + length < target) : (length += 1) {
                const position = self.head + length;
                const index: usize = @intCast(position % self.capacity);
                if (self.slotState(index).load(.acquire) != format.tag(position + 1, .committed)) break;
                destination[length] = self.liveRecord(index);
            }
        }
        return destination[0..length];
    }

    /// Checked batch variant for the collector. A later corrupt slot fails the
    /// whole peek operation and retains every committed slot as evidence.
    pub fn peekBatchChecked(self: *Journal, destination: []Record) ![]Record {
        if (destination.len == 0) return destination[0..0];
        destination[0] = (try self.peekChecked()) orelse return destination[0..0];
        var length: usize = 1;
        if (self.recovery_cursor < self.recovery_length) {
            while (length < destination.len and self.recovery_cursor + length < self.recovery_length) : (length += 1) {
                const index = self.recovery_order[self.recovery_cursor + length];
                destination[length] = try self.validateSlot(index, self.slotState(index).load(.acquire));
            }
        } else {
            const target = self.tail().load(.acquire);
            while (length < destination.len and self.head + length < target) : (length += 1) {
                const position = self.head + length;
                const index: usize = @intCast(position % self.capacity);
                const marker = self.slotState(index).load(.acquire);
                if (marker != format.tag(position + 1, .committed)) {
                    if (marker != 0 and marker != format.tag(position + 1, .reserved) and marker != format.tag(position + 1, .aborted)) return error.CorruptRecord;
                    break;
                }
                destination[length] = try self.validateSlot(index, marker);
            }
        }
        return destination[0..length];
    }

    fn liveRecord(self: *Journal, index: usize) Record {
        const bytes = self.slotBytes(index);
        return .{
            .sequence = format.get(u64, bytes, 8),
            .generation = format.get(u64, bytes, 16),
            .payload = bytes[format.slot_header_bytes..][0..format.get(u32, bytes, 24)],
            .slot = index,
            .schema_ref = self.readSlotSchema(bytes) catch unreachable,
        };
    }

    /// Call only after every required route has completed writing this record.
    /// A crash between output and this acknowledgement can cause replay;
    /// successful written reclaim alone does not guarantee power-loss recovery.
    pub fn release(self: *Journal, record: Record) !void {
        return self.releaseAfter(record, .written);
    }

    /// Durable reclaim additionally requires the caller to have synced every
    /// required output. The journal persists reclamation before enabling reuse.
    /// A sync failure leaves the record owned and retryable by the consumer.
    pub fn releaseAfter(self: *Journal, record: Record, boundary: ReclaimBoundary) !void {
        if (record.slot >= self.capacity) return error.InvalidRecord;
        const expected = (try self.peekChecked()) orelse return error.InvalidRecord;
        if (expected.sequence != record.sequence or expected.slot != record.slot or expected.generation != record.generation) return error.InvalidRecord;
        if (boundary == .durable) {
            self.sync_mutex.lockUncancelable(self.io);
            defer self.sync_mutex.unlock(self.io);
            // Commit bytes first; then alternate checksummed checkpoints. A
            // torn checkpoint falls back to the previous complete copy and
            // produces replay rather than premature acknowledgement.
            try self.mapping.sync();
            const epoch = std.math.add(u64, self.checkpoint_epoch, 1) catch return error.SequenceExhausted;
            format.writeCheckpoint(self.mapping.bytes, @intCast((epoch - 1) % 2), epoch, record.sequence);
            try self.mapping.sync();
            self.checkpoint_epoch = epoch;
            self.durable_reclaimed.store(record.sequence, .release);
            // Persist the invalidated slot before exposing it for reuse. If
            // sync fails restore its live marker and retain consumer ownership;
            // the durable checkpoint still makes crash recovery safe.
            self.slotState(record.slot).store(0, .release);
            self.mapping.sync() catch |err| {
                self.slotState(record.slot).store(format.tag(record.sequence, .committed), .release);
                return err;
            };
        }
        self.reclaim(record.slot, record.sequence);
        if (self.recovery_cursor < self.recovery_length) {
            self.recovery_cursor += 1;
            const completed_prefix = if (self.recovery_cursor < self.recovery_length) format.get(u64, self.slotBytes(self.recovery_order[self.recovery_cursor]), 8) - 1 else self.recovery_tail;
            // Only this opening's old tail has been scanned for abandoned
            // reservations. New live reservations remain consumer-owned.
            self.advanceWritten(completed_prefix);
        } else self.head += 1;
    }

    /// Identity-only counterpart of the checked peek used by `releaseAfter`.
    /// The borrowed record must have been returned by this journal's checked
    /// peek and not yet released. Payload bytes are deliberately not rehashed:
    /// the consumer already observed them and the ring protocol keeps the slot
    /// write-protected for producers until reclaim.
    fn validateReclaimIdentity(self: *Journal, record: Record) !void {
        if (record.sequence == 0 or record.sequence > format.max_sequence) return error.InvalidRecord;
        if ((record.sequence - 1) % self.capacity != record.slot) return error.InvalidRecord;
        if (record.generation != self.generation(record.sequence)) return error.InvalidRecord;
        const bytes = self.slotBytes(record.slot);
        if (format.get(u64, bytes, 8) != record.sequence or format.get(u64, bytes, 16) != record.generation) return error.InvalidRecord;
        if (self.slotState(record.slot).load(.acquire) != format.tag(record.sequence, .committed)) return error.InvalidRecord;
        if (self.recovery_cursor < self.recovery_length) {
            if (self.recovery_order[self.recovery_cursor] != record.slot) return error.InvalidRecord;
        } else if (record.sequence != self.head + 1) return error.InvalidRecord;
    }

    fn advanceWritten(self: *Journal, sequence: u64) void {
        if (self.producer_mode == .shared) {
            // Publish preceding writes to acquire readers observing new progress.
            // Slot reuse and later runtime accounting have separate boundaries.
            _ = self.written().fetchMax(sequence, .release);
        } else if (sequence > self.single.consumer_written.load(.monotonic)) self.single.consumer_written.store(sequence, .release);
    }

    fn reclaim(self: *Journal, index: usize, sequence: u64) void {
        self.slotState(index).store(0, .release);
        if (self.producer_mode == .shared) {
            _ = self.occupied.fetchSub(1, .monotonic);
        } else {
            // Count release before publishing the free turn, so even the
            // recovery-gap fallback observes accounting before it reuses space.
            self.single.released_total.store(self.single.released_total.load(.monotonic) + 1, .release);
        }
        self.advanceWritten(sequence);
        self.turns[index].store(self.nextTurn(self.tail().load(.monotonic), index), .release);
        if (self.producer_mode == .single) {
            self.single.consumer_free_position.store(sequence, .release);
        }
    }

    /// Persist journal data and metadata. Runtime must separately sync outputs;
    /// this function never declares output written/durable on its behalf.
    pub fn sync(self: *Journal) !void {
        self.sync_mutex.lockUncancelable(self.io);
        defer self.sync_mutex.unlock(self.io);
        // SPSC consumer progress has its own cache line. Mirroring only at
        // sync avoids consumer writes beside the producer's mapped tail.
        if (self.producer_mode == .single) self.written().store(self.writtenTarget(), .release);
        try self.mapping.sync();
    }

    /// Confirm the already-written consumer progress after every required
    /// output has completed durable sync. The caller must prevent consumer
    /// advancement throughout this operation. Committed unwritten records
    /// remain owned; a checkpoint never advances beyond writtenTarget.
    pub fn checkpointWrittenDurable(self: *Journal) !void {
        self.sync_mutex.lockUncancelable(self.io);
        defer self.sync_mutex.unlock(self.io);
        const sequence = self.writtenTarget();
        if (sequence > self.reservationTarget()) return error.CorruptHeader;
        if (self.producer_mode == .single) self.written().store(sequence, .release);
        try self.mapping.sync();
        if (sequence <= self.durable_reclaimed.load(.acquire)) return;
        const epoch = std.math.add(u64, self.checkpoint_epoch, 1) catch return error.SequenceExhausted;
        format.writeCheckpoint(self.mapping.bytes, @intCast((epoch - 1) % 2), epoch, sequence);
        try self.mapping.sync();
        self.checkpoint_epoch = epoch;
        self.durable_reclaimed.store(sequence, .release);
    }
    pub fn pending(self: *const Journal) usize {
        if (self.producer_mode == .single) {
            const released = self.single.released_total.load(.acquire);
            return @intCast(self.single.reserved_total.load(.acquire) - released);
        }
        return self.occupied.load(.monotonic);
    }
    pub fn count(self: *const Journal) usize {
        return self.pending();
    }
    pub fn highWater(self: *const Journal) usize {
        return self.high_water.load(.monotonic);
    }
    pub fn reservationTarget(self: *const Journal) u64 {
        return self.tail().load(.acquire);
    }
    pub fn writtenTarget(self: *const Journal) u64 {
        if (self.producer_mode == .single) return self.single.consumer_written.load(.acquire);
        return self.written().load(.acquire);
    }
    pub fn durableReclaimedTarget(self: *const Journal) u64 {
        return self.durable_reclaimed.load(.acquire);
    }
    pub fn maxRecordBytes(self: *const Journal) usize {
        return self.max_record_bytes;
    }
    pub fn sessionIdentity(self: *const Journal) [16]u8 {
        return self.mapping.bytes[40..56].*;
    }
    pub fn mappedBytes(self: *const Journal) usize {
        return self.mapping.bytes.len;
    }

    /// Producers/consumer must have stopped before deinit. Pending records
    /// survive process exit; no implicit output acknowledgement or sync occurs.
    pub fn deinit(self: *Journal) void {
        const allocator = self.allocator;
        if (self.schema) |*registry| registry.deinit();
        self.mapping.deinit();
        allocator.free(self.turns);
        allocator.free(self.recovery_order);
        allocator.destroy(self);
    }
};

test {
    _ = @import("tests.zig");
    _ = @import("schema_journal_tests.zig");
}

test "memory journal can opt out of slot CRC" {
    var journal = try Journal.createMemory(std.testing.allocator, std.testing.io, .{
        .path = "",
        .capacity = 2,
        .max_record_bytes = 64,
        .verify_crc = false,
    });
    defer journal.deinit();
    var reservation = try journal.reserve();
    @memcpy(reservation.buffer()[0..7], "payload");
    try reservation.commit(7);
    format.put(u32, journal.slotBytes(reservation.slot), 28, 0xdeadbeef);
    const record = journal.peek() orelse return error.MissingRecord;
    try std.testing.expectEqualSlices(u8, "payload", record.payload);
}
