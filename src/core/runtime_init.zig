//! Initialization and rollback of the stable runtime owner. All allocations,
//! filesystem mappings and thread starts are confined to this cold path.
const std = @import("std");
const builtin = @import("builtin");
const Runtime = @import("runtime.zig").Runtime;
const types = @import("runtime_types.zig");
const Options = types.Options;
const Route = types.Route;
const Field = @import("field.zig").Field;
const Filter = @import("../config/filter.zig").Filter;
const DynamicFilter = @import("../config/reload.zig").DynamicFilter;
const Journal = @import("../journal/journal.zig").Journal;
const schema_module = @import("../journal/schema.zig");
const thread_module = @import("thread_registry.zig");
const sampler_module = @import("../pipeline/sampler.zig");
const redact_module = @import("../pipeline/redact.zig");
const diagnostics_module = @import("diagnostics.zig");
const control_module = @import("control.zig");
const configurations = @import("../config/routes.zig");
const RenderCache = @import("render_cache.zig").RenderCache;

pub fn create(allocator: std.mem.Allocator, io: std.Io, options: Options, comptime worker_callback: anytype, comptime control_callback: anytype, comptime decode_callback: anytype) !*Runtime {
    if (builtin.single_threaded and options.submission != .sync) return error.ThreadsUnavailable;
    if (options.routes.len == 0 or options.routes.len > 64 or options.max_encoded_record_bytes == 0) return error.InvalidOptions;
    for (options.routes) |route| if (route.max_encoded_record_bytes) |limit| if (limit > options.max_encoded_record_bytes) return error.EncodedRecordBudgetExceeded;
    if (options.consumer_batches_per_queue == 0 or options.consumer_batches_per_queue > 4) return error.InvalidOptions;
    if (options.journal != null and options.memory_queue != null) return error.ConflictingQueueStorage;
    const queue_options: ?@import("../journal/journal.zig").Options = if (options.memory_queue) |memory| .{ .path = "", .capacity = memory.capacity, .max_record_bytes = memory.max_record_bytes, .schema_capacity = memory.schema_capacity, .max_schema_bytes = memory.max_schema_bytes, .recover = false, .verify_crc = memory.verify_crc } else options.journal;
    if (options.submission != .sync and queue_options == null) return error.JournalRequired;
    if (options.submission == .sync and queue_options != null) return error.InvalidOptions;
    if (options.max_thread_channels > 64 or (options.max_thread_channels != 0 and queue_options == null)) return error.InvalidOptions;
    if (options.memory_queue != null and options.recovery_versions.len != 0) return error.RecoveryRequiresMmap;
    if (options.memory_queue != null) for (options.routes) |*route| if (route.reclaim_after == .durable) return error.DurableReclaimRequiresMmap;
    if (options.submission == .low_latency and options.max_thread_channels == 0) return error.ThreadChannelsRequired;
    if (options.render_cache) {
        if (queue_options == null) return error.RenderCacheUnsupported;
        if (options.render_cache_record_bytes == 0 or options.render_cache_record_bytes > options.max_encoded_record_bytes) return error.InvalidRenderCache;
    }
    if (queue_options) |journal_options| {
        const layout = try @import("../journal/format.zig").layout(journal_options.capacity, journal_options.max_record_bytes);
        var total = if (journal_options.schema_capacity == 0) layout.size else (try schema_module.layout(layout.size, journal_options.schema_capacity, journal_options.max_schema_bytes)).size;
        if (options.max_thread_channels != 0) {
            const channel_layout = try @import("../journal/format.zig").layout(options.thread_channel_capacity, journal_options.max_record_bytes);
            const channel_size = if (journal_options.schema_capacity == 0) channel_layout.size else (try schema_module.layout(channel_layout.size, journal_options.schema_capacity, journal_options.max_schema_bytes)).size;
            total = std.math.add(usize, total, try std.math.mul(usize, channel_size, options.max_thread_channels)) catch return error.JournalBudgetExceeded;
        }
        if (total > options.max_journal_bytes) return error.JournalBudgetExceeded;
    }
    const self = try allocator.create(Runtime);
    errdefer allocator.destroy(self);
    const filter = try DynamicFilter.createBound(allocator, io, options.filter, options.initial_route_generation);
    errdefer filter.destroy();
    const output = try allocator.alloc(u8, options.max_encoded_record_bytes);
    errdefer allocator.free(output);
    const configuration = try configurations.Manager.create(allocator, io, .{
        .capacity = options.configuration_slots,
        .max_config_bytes = options.max_configuration_bytes,
        .initial_routes = options.routes,
        .redaction = options.redaction,
        .sampling = options.sampling,
        .sample_bypass = options.sample_bypass,
        .predicate = options.predicate,
        .default_filter = options.filter,
        .initial_generation = options.initial_route_generation,
        .require_recovery_identity = options.journal != null,
    });
    errdefer {
        configuration.discardPinsAfterStop();
        configuration.abandon();
    }
    for (options.recovery_versions) |version| {
        for (version.routes) |route| if (route.max_encoded_record_bytes) |limit| if (limit > options.max_encoded_record_bytes) return error.EncodedRecordBudgetExceeded;
        try configuration.addRecovery(version.generation, version.routes, version.policy);
    }
    const caches = try allocator.create(Runtime.Caches);
    errdefer allocator.destroy(caches);
    caches.* = .{};
    const journal = if (queue_options) |opts| (if (options.memory_queue != null) try Journal.createMemory(allocator, io, opts) else try Journal.create(allocator, io, opts)) else null;
    errdefer if (journal) |j| j.deinit();
    var identity: [8]u8 = undefined;
    try io.randomSecure(&identity);
    self.* = .{
        .allocator = allocator,
        .io = io,
        .configuration_handle = configuration,
        .configuration_cache_handle = caches,
        .filter_handle = filter,
        .submission = options.submission,
        .journal = journal,
        .overflow = options.overflow,
        .idle = options.idle orelse if (options.submission == .low_latency) .spin else .sleep,
        .consumer_batches_per_queue = options.consumer_batches_per_queue,
        .output = output,
        .session = std.mem.readInt(u64, &identity, .little),
        .clock = options.clock,
        .diagnostics = diagnostics_module.Reporter.init(options.diagnostics),
    };
    if (options.journal != null and !@import("../platform/mapping.zig").durable_supported) self.historical_durable_supported.store(false, .monotonic);
    if (options.max_thread_channels != 0) {
        self.thread_registry = try thread_module.Registry(Runtime).create(allocator, io, self, .{
            .max_channels = options.max_thread_channels,
            .journal_path_prefix = queue_options.?.path,
            .capacity = options.thread_channel_capacity,
            .max_record_bytes = queue_options.?.max_record_bytes,
            .schema_capacity = queue_options.?.schema_capacity,
            .max_schema_bytes = queue_options.?.max_schema_bytes,
            .memory = options.memory_queue != null,
            .verify_crc = queue_options.?.verify_crc,
        });
    }
    errdefer if (self.thread_registry) |registry| registry.destroy();
    if (options.render_cache) {
        var cache_journals: [65]?*Journal = @splat(null);
        var cache_count: usize = 0;
        if (self.journal) |store| {
            cache_journals[cache_count] = store;
            cache_count += 1;
        }
        if (self.thread_registry) |registry| for (registry.activeJournals()) |store| {
            cache_journals[cache_count] = store;
            cache_count += 1;
        };
        const render_caches = try allocator.alloc(?*RenderCache, cache_count);
        errdefer allocator.free(render_caches);
        @memset(render_caches, null);
        const render_journals = try allocator.alloc(?*Journal, cache_count);
        errdefer allocator.free(render_journals);
        var created: usize = 0;
        errdefer for (render_caches[0..created]) |maybe_cache| if (maybe_cache) |cache| cache.destroy();
        for (cache_journals[0..cache_count], 0..) |maybe_journal, index| {
            render_journals[index] = maybe_journal;
            render_caches[index] = try RenderCache.create(allocator, maybe_journal.?.capacity, options.render_cache_record_bytes);
            created += 1;
        }
        caches.render_caches = render_caches;
        caches.render_journals = render_journals;
    }
    errdefer {
        for (caches.render_caches) |maybe_cache| if (maybe_cache) |cache| cache.destroy();
        if (caches.render_caches.len != 0) allocator.free(caches.render_caches);
        if (caches.render_journals.len != 0) allocator.free(caches.render_journals);
    }
    var recovery_journals: [65]*Journal = undefined;
    var journal_count: usize = 0;
    if (journal) |store| {
        recovery_journals[journal_count] = store;
        journal_count += 1;
    }
    if (self.thread_registry) |registry| for (registry.activeJournals()) |channel| {
        recovery_journals[journal_count] = channel;
        journal_count += 1;
    };
    // Validate every binding before retaining any record, not just the first
    // record. A missing historical target cannot be silently redirected.
    for (recovery_journals[0..journal_count]) |store| {
        var index: usize = 0;
        while (try store.recoveryRecordAt(index)) |record| : (index += 1) {
            var recovered_fields: [@import("codec.zig").decode_scratch_fields]Field = undefined;
            const event = try decode_callback(store, record, &recovered_fields);
            if (event.channel > (if (self.thread_registry) |registry| registry.channelCount() else 0)) return error.InvalidChannel;
            const view = try configuration.find(event.route_generation, event.route_fingerprint);
            view.release();
        }
    }
    for (recovery_journals[0..journal_count]) |store| {
        var index: usize = 0;
        while (try store.recoveryRecordAt(index)) |record| : (index += 1) {
            var recovered_fields: [@import("codec.zig").decode_scratch_fields]Field = undefined;
            const event = try decode_callback(store, record, &recovered_fields);
            const view = try configuration.find(event.route_generation, event.route_fingerprint);
            view.snapshot.retainChannel(event.channel);
            view.release();
        }
    }
    var all_views: [64]configurations.View = undefined;
    const views = try configuration.retainedViews(&all_views);
    for (views) |view| {
        for (view.snapshot.routes) |*route| if (route.delivery == .required and !route.sink.supports_durable) self.historical_durable_supported.store(false, .monotonic);
        view.release();
    }
    if (!builtin.single_threaded) {
        self.control = try control_module.Control.create(allocator, io, self, control_callback);
        errdefer self.control.?.destroy();
        if (journal) |j| {
            self.counters.recovered.store(@intCast(j.pending()), .monotonic);
            if (self.thread_registry) |registry| for (registry.activeJournals()) |channel| {
                _ = self.counters.recovered.fetchAdd(@intCast(channel.pending()), .monotonic);
            };
            self.worker = try std.Thread.spawn(.{}, worker_callback, .{self});
        }
    }
    return self;
}
