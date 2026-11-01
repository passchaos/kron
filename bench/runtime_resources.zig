//! Requested allocation footprint at stable Runtime initialization. Native IO
//! and OS mappings outside its allocator are not included in this byte count.
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.ExpectedModeDirectoryThreadBudget;
    const mode = args[1];
    if (!std.mem.eql(u8, mode, "sync") and !std.mem.eql(u8, mode, "memory") and !std.mem.eql(u8, mode, "mmap")) return error.InvalidMode;
    const budget = try std.fmt.parseInt(usize, args[3], 10);
    if (budget > 64 or (std.mem.eql(u8, mode, "sync") and budget != 0)) return error.InvalidBudget;
    const sync = std.mem.eql(u8, mode, "sync");
    const mapped = std.mem.eql(u8, mode, "mmap");
    const path = try std.fmt.allocPrint(init.arena.allocator(), "{s}/resources.journal", .{args[2]});
    var bytes: [8192]u8 = undefined;
    var sink = kron.MemorySink.initBuffer(&bytes);
    var allocator = std.testing.FailingAllocator.init(init.gpa, .{});
    const started = std.Io.Clock.awake.now(init.io).nanoseconds;
    const runtime = try kron.Runtime.create(allocator.allocator(), init.io, .{
        .submission = if (sync) .sync else if (budget == 0) .asynchronous else .low_latency,
        .memory_queue = if (!sync and !mapped) .{ .capacity = 8, .max_record_bytes = 512 } else null,
        .journal = if (mapped) .{ .path = path, .capacity = 8, .max_record_bytes = 512, .recover = false } else null,
        .max_thread_channels = budget,
        .thread_channel_capacity = 8,
        .routes = &.{.{ .name = "memory", .sink = sink.sink(), .recovery_identity = "resource-benchmark" }},
    });
    var live = true;
    defer if (live) runtime.destroy();
    const initialized = std.Io.Clock.awake.now(init.io).nanoseconds;
    const requested_live_bytes = allocator.allocated_bytes - allocator.freed_bytes;
    const initialization_allocations = allocator.allocations;
    const health = runtime.health();
    const thread_state_bytes = if (@hasField(kron.Runtime, "thread_states")) runtime.thread_states.len * @sizeOf(@TypeOf(runtime.thread_states[0])) else @sizeOf(@TypeOf(runtime.channel_counters));
    allocator.fail_index = allocator.alloc_index;
    allocator.resize_fail_index = allocator.resize_index;
    _ = try runtime.scoped("resource").tryEmit(.info, "footprint", .{ .id = @as(u32, 42) });
    try runtime.flush(.written);
    try runtime.shutdown(.drain);
    if (runtime.health().written != 1 or allocator.has_induced_failure) return error.IncompleteOutput;
    runtime.destroy();
    live = false;
    if (allocator.allocated_bytes != allocator.freed_bytes) return error.UnreleasedAllocations;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try std.json.Stringify.value(.{
        .benchmark = "runtime_requested_resources",
        .mode = mode,
        .thread_budget = budget,
        .requested_live_bytes = requested_live_bytes,
        .initialization_allocations = initialization_allocations,
        .initialization_ns = initialized - started,
        .runtime_owner_bytes = @sizeOf(kron.Runtime),
        .reported_thread_state_bytes = thread_state_bytes,
        .queue_reserved_bytes = health.queue_reserved_bytes,
        .journal_reserved_bytes = health.journal_reserved_bytes,
        .allocator_freed_all = true,
        .written = 1,
    }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
