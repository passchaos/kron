//! Per-channel file-backed SPSC journal. The same recoverable slot protocol is
//! used as Journal, but producer reservation has no tail CAS or counter RMW.
//! A channel has exactly one owner thread and one collector. Pool orchestration
//! lives above this module; retirement retains data until explicit deinit.
const std = @import("std");
const store = @import("journal.zig");

pub const Options = store.Options;
pub const ProducerToken = store.SingleProducerToken;
pub const Reservation = store.Reservation;
pub const Record = store.Record;
pub const ControlBlock = store.SingleProducerControl;
pub const SchemaRef = store.SchemaRef;
pub const currentThreadCookie = store.currentThreadCookie;
pub const registerCurrentThreadCookie = store.registerCurrentThreadCookie;

pub const Stats = struct {
    owner: std.Thread.Id,
    owner_cookie: u64,
    generation: u64,
    retired: bool,
    pending: usize,
    high_water: usize,
    reservation_target: u64,
    written_target: u64,
    durable_reclaimed_target: u64,
};

pub const SpscJournal = struct {
    allocator: std.mem.Allocator,
    journal: *store.Journal,
    control: *const ControlBlock,

    pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options) !*SpscJournal {
        return createInternal(allocator, io, options, false);
    }

    pub fn createMemory(allocator: std.mem.Allocator, io: std.Io, options: Options) !*SpscJournal {
        return createInternal(allocator, io, options, true);
    }

    fn createInternal(allocator: std.mem.Allocator, io: std.Io, options: Options, memory: bool) !*SpscJournal {
        const journal = if (memory) try store.Journal.createMemorySingleProducer(allocator, io, options) else try store.Journal.createSingleProducer(allocator, io, options);
        errdefer journal.deinit();
        const self = try allocator.create(SpscJournal);
        self.* = .{ .allocator = allocator, .journal = journal, .control = try journal.singleProducerControl() };
        return self;
    }

    /// Capture this attachment's generation for handles retained by runtime.
    /// reserveWithToken rejects that handle after retirement/reactivation.
    pub fn token(self: *SpscJournal) !ProducerToken {
        return self.journal.singleProducerToken();
    }

    pub fn reserve(self: *SpscJournal) !Reservation {
        return self.journal.reserveSingleProducer(try self.token());
    }

    pub fn reserveWithToken(self: *SpscJournal, producer: ProducerToken) !Reservation {
        return self.journal.reserveSingleProducer(producer);
    }

    pub fn reserveWithSchema(self: *SpscJournal, reference: SchemaRef) !Reservation {
        return self.journal.reserveSingleProducerWithSchema(try self.token(), reference);
    }

    pub fn reserveWithTokenAndSchema(self: *SpscJournal, producer: ProducerToken, reference: SchemaRef) !Reservation {
        return self.journal.reserveSingleProducerWithSchema(producer, reference);
    }

    /// Owner thread only. Finish/abort reservations first; committed records
    /// remain readable and can be drained by the collector while retired.
    pub fn retire(self: *SpscJournal) !void {
        return self.journal.retireSingleProducer(try self.token());
    }

    /// A retired channel binds to the caller's thread with a fresh generation.
    /// Pending data and monotonically increasing record sequences are retained.
    pub fn reactivate(self: *SpscJournal) !ProducerToken {
        return self.journal.reactivateSingleProducer();
    }

    pub fn stats(self: *const SpscJournal) Stats {
        return .{
            .owner = self.control.owner(),
            .owner_cookie = self.control.ownerCookie(),
            .generation = self.control.generation(),
            .retired = self.control.retired(),
            .pending = self.journal.pending(),
            .high_water = self.journal.highWater(),
            .reservation_target = self.journal.reservationTarget(),
            .written_target = self.journal.writtenTarget(),
            .durable_reclaimed_target = self.journal.durableReclaimedTarget(),
        };
    }

    /// Ownership is borrowed, including payload slices and ProducerTokens.
    /// Stop producer/collector/sync callers before destroying the control block.
    pub fn deinit(self: *SpscJournal) void {
        const allocator = self.allocator;
        self.journal.deinit();
        allocator.destroy(self);
    }
};

test {
    _ = @import("spsc_tests.zig");
}
