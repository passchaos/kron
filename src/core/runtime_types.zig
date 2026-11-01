//! Configuration and observable state shared by the runtime and control APIs.
const std = @import("std");
const Level = @import("level.zig").Level;
const LoggerModule = @import("logger.zig");
const JournalModule = @import("../journal/journal.zig");
const Sink = @import("../sink/interface.zig").Sink;
const Filter = @import("../config/filter.zig").Filter;
const encoder = @import("../encoder/root.zig");
const sampler_module = @import("../pipeline/sampler.zig");
const redact_module = @import("../pipeline/redact.zig");
const Clock = @import("../platform/clock.zig").Clock;
const diagnostics_module = @import("diagnostics.zig");
const Atomic = std.atomic.Value;

pub const Admission = LoggerModule.Admission;
pub const BeginResult = LoggerModule.BeginResult;
pub const EmitResult = LoggerModule.EmitResult;
pub const Submission = enum { sync, asynchronous, low_latency };
pub const QueueStorage = enum { none, memory, mmap };
pub const MemoryQueueOptions = struct {
    capacity: usize = 256,
    max_record_bytes: usize = 8192,
    schema_capacity: usize = 0,
    max_schema_bytes: usize = 8192,
};
pub const Overflow = enum { block, drop_newest, fallback_sync };
pub const Flush = enum { drain, written, durable };
pub const Delivery = enum { required, best_effort };
pub const Idle = enum { sleep, spin };
pub const State = enum(u8) { running, closing, closed };

pub const SinkRelease = struct {
    context: *anyopaque,
    release: *const fn (*anyopaque) void,
};

pub const RoutePolicy = struct {
    redaction: []const redact_module.Rule = &.{},
    sampling: sampler_module.Config = .none,
    sample_bypass: Level = .warn,
    default_filter: ?[]const u8 = null,
    predicate: ?[]const u8 = null,
};

pub const RecoveryVersion = struct {
    generation: u64,
    routes: []const RouteOptions,
    policy: RoutePolicy = .{},
};

pub const RouteOptions = struct {
    name: []const u8,
    sink: Sink,
    format: encoder.Format = .json,
    /// Opt-in RFC3339 with fixed offset or system local time and precision.
    /// A route-owned second cache is updated only during serialized delivery.
    timestamp: ?@import("../time/root.zig").FormatOptions = null,
    /// An independent route filter; null inherits the runtime filter.
    filter: ?[]const u8 = null,
    min_level: ?Level = null,
    delivery: Delivery = .required,
    reclaim_after: JournalModule.ReclaimBoundary = .written,
    /// Stable recovery binding for custom sinks without recovery_identity.
    recovery_identity: ?[]const u8 = null,
    /// Explicit transfer of a resource lease. Omit for caller-owned sinks.
    release: ?SinkRelease = null,
    predicate: ?[]const u8 = null,
    /// Additional output-only redaction. Capture-wide protection is separate.
    redaction: []const redact_module.Rule = &.{},
    /// null inherits the Runtime sampler; .none explicitly bypasses it here.
    sampling: ?sampler_module.Config = null,
    sample_bypass: Level = .warn,
    max_encoded_record_bytes: ?usize = null,
};

pub const Options = struct {
    routes: []const RouteOptions,
    submission: Submission = .sync,
    journal: ?JournalModule.Options = null,
    /// Volatile bounded asynchronous capture. Mutually exclusive with journal.
    memory_queue: ?MemoryQueueOptions = null,
    overflow: Overflow = .block,
    filter: []const u8 = "info",
    sampling: sampler_module.Config = .none,
    sample_bypass: Level = .warn,
    redaction: []const redact_module.Rule = &.{},
    max_encoded_record_bytes: usize = 64 * 1024,
    idle: ?Idle = null,
    /// Maximum checked batches served from one queue before visiting peers.
    /// 1..4; smaller values trade batch locality for shorter peer service gaps.
    consumer_batches_per_queue: usize = 4,
    max_thread_channels: usize = 0,
    thread_channel_capacity: usize = 256,
    max_journal_bytes: usize = 256 * 1024 * 1024,
    clock: Clock = .{},
    diagnostics: diagnostics_module.Options = .{},
    predicate: ?[]const u8 = null,
    configuration_slots: usize = 8,
    max_configuration_bytes: usize = 2 * 1024 * 1024,
    initial_route_generation: u64 = 1,
    recovery_versions: []const RecoveryVersion = &.{},
};

pub const Health = struct {
    accepted: u64,
    filtered: u64,
    sampled: u64,
    dropped_full: u64,
    dropped_oversize: u64,
    rejected_closing: u64,
    written: u64,
    write_errors: u64,
    flush_errors: u64,
    sync_errors: u64,
    capture_errors: u64,
    recovered: u64,
    journal_pending: usize,
    journal_high_water: usize,
    worker_alive: bool,
    journal_reserved_bytes: usize,
    queue_storage: QueueStorage,
    queue_reserved_bytes: usize,
    thread_channels: usize,
    last_error: ?anyerror,
    state: State,
};

pub const Counters = struct {
    accepted: Atomic(u64) align(64) = .init(0),
    filtered: Atomic(u64) = .init(0),
    sampled: Atomic(u64) = .init(0),
    dropped_full: Atomic(u64) = .init(0),
    dropped_oversize: Atomic(u64) = .init(0),
    rejected_closing: Atomic(u64) = .init(0),
    written: Atomic(u64) align(64) = .init(0),
    write_errors: Atomic(u64) = .init(0),
    flush_errors: Atomic(u64) = .init(0),
    sync_errors: Atomic(u64) = .init(0),
    capture_errors: Atomic(u64) = .init(0),
    recovered: Atomic(u64) = .init(0),
};

pub const Route = struct {
    name: []u8,
    sink: Sink,
    format: encoder.Format,
    /// Mutable only under the runtime's delivery lock. Owned by this route.
    timestamp: ?*@import("../time/root.zig").Formatter = null,
    filter: ?Filter,
    min_level: ?Level,
    delivery: Delivery,
    reclaim_after: JournalModule.ReclaimBoundary,
    recovery_identity: ?[]u8,
    release: ?SinkRelease = null,
    predicate: ?@import("../pipeline/predicate.zig").Predicate = null,
    policy: ?*@import("../config/output_policy.zig").Policy = null,
};
