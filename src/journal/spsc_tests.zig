const std = @import("std");
const spsc = @import("spsc.zig");
const journal = @import("journal.zig");
const format = @import("format.zig");
const testing = std.testing;

fn optionsFor(tmp: *const testing.TmpDir, buffer: []u8, capacity: usize) !spsc.Options {
    return .{ .path = try std.fmt.bufPrint(buffer, ".zig-cache/tmp/{s}/spsc.journal", .{tmp.sub_path}), .capacity = capacity, .max_record_bytes = 32 };
}
fn append(channel: *spsc.SpscJournal, bytes: []const u8) !void {
    var reservation = try channel.reserve();
    errdefer reservation.abort();
    @memcpy(reservation.buffer()[0..bytes.len], bytes);
    try reservation.commit(bytes.len);
}

test "SPSC full wrap and exclusive producer mode preserve MPSC API" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const channel = try spsc.SpscJournal.create(testing.allocator, testing.io, try optionsFor(&tmp, &buffer, 2));
    defer channel.deinit();
    try testing.expectError(error.ExclusiveProducer, channel.journal.reserve());
    try append(channel, "first");
    try append(channel, "second");
    try testing.expectError(error.Full, channel.reserve());
    try testing.expectEqual(@as(usize, 2), channel.stats().pending);
    for (0..2) |_| try channel.journal.release((try channel.journal.peekChecked()).?);
    for (0..64) |index| {
        try append(channel, "wrapped");
        const record = (try channel.journal.peekChecked()).?;
        try testing.expectEqual(@as(u64, index + 3), record.sequence);
        try testing.expectEqual(@as(u64, (index + 2) / 2 + 1), record.generation);
        try channel.journal.release(record);
    }
    try testing.expectEqual(@as(usize, 0), channel.stats().pending);
    try testing.expectEqual(@as(usize, 2), channel.stats().high_water);
    // Shared Journal instances keep using the original producer path and do
    // not accept a token from the exclusive instance.
    var second_buffer: [128]u8 = undefined;
    const other_path = try std.fmt.bufPrint(&second_buffer, ".zig-cache/tmp/{s}/shared.journal", .{tmp.sub_path});
    const shared = try journal.Journal.create(testing.allocator, testing.io, .{ .path = other_path, .capacity = 2, .max_record_bytes = 32 });
    defer shared.deinit();
    try testing.expectError(error.WrongProducerMode, shared.reserveSingleProducer(try channel.token()));
    var shared_reservation = try shared.reserve();
    shared_reservation.abort();
    try testing.expect(shared.peek() == null);
}

test "SPSC validates owner thread on reserve commit and retirement" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const channel = try spsc.SpscJournal.create(testing.allocator, testing.io, try optionsFor(&tmp, &buffer, 2));
    defer channel.deinit();
    var reservation = try channel.reserve();
    @memcpy(reservation.buffer()[0..5], "owner");
    const Worker = struct {
        fn run(store: *spsc.SpscJournal, record: *journal.Reservation, flags: *[3]bool) void {
            if (store.reserve()) |_| {} else |err| flags[0] = err == error.WrongThread;
            record.commit(5) catch |err| {
                flags[1] = err == error.WrongThread;
            };
            store.retire() catch |err| {
                flags[2] = err == error.WrongThread;
            };
        }
    };
    var flags = [_]bool{false} ** 3;
    const worker = try std.Thread.spawn(.{}, Worker.run, .{ channel, &reservation, &flags });
    worker.join();
    for (flags) |flag| try testing.expect(flag);
    try testing.expectError(error.OutstandingReservation, channel.retire());
    try reservation.commit(5);
    try channel.retire();
    try testing.expectEqualStrings("owner", (try channel.journal.peekChecked()).?.payload);
    try channel.journal.release((try channel.journal.peekChecked()).?);
}

test "SPSC rejects a reused thread id with an unregistered or different TLS cookie" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const channel = try spsc.SpscJournal.create(testing.allocator, testing.io, try optionsFor(&tmp, &buffer, 2));
    defer channel.deinit();
    const owner_id = channel.control.owner();
    const owner_cookie = channel.control.ownerCookie();
    const producer = try channel.token();
    try testing.expect(owner_cookie != 0);
    try testing.expectEqual(owner_cookie, spsc.currentThreadCookie());
    const Worker = struct {
        fn run(store: *spsc.SpscJournal, token: spsc.ProducerToken, original_cookie: u64, flags: *[5]bool) void {
            flags[0] = spsc.currentThreadCookie() == 0;
            // Simulate the kernel reusing the departed owner's numeric TID.
            // Its independent cookie remains unchanged, so a fresh thread
            // cannot take over the still-active control block.
            store.journal.single.owner_id.store(std.Thread.getCurrentId(), .release);
            if (store.reserveWithToken(token)) |_| {} else |err| flags[1] = err == error.WrongThread;
            flags[2] = spsc.currentThreadCookie() == 0;
            const cookie = spsc.registerCurrentThreadCookie() catch return;
            flags[3] = cookie != 0 and cookie != original_cookie;
            if (store.reserveWithToken(token)) |_| {} else |err| flags[4] = err == error.WrongThread;
        }
    };
    var flags = [_]bool{false} ** 5;
    const worker = try std.Thread.spawn(.{}, Worker.run, .{ channel, producer, owner_cookie, &flags });
    worker.join();
    channel.journal.single.owner_id.store(owner_id, .release);
    for (flags) |flag| try testing.expect(flag);
    try testing.expectEqual(owner_cookie, channel.control.ownerCookie());
    try testing.expectEqual(@as(u64, 0), channel.journal.reservationTarget());
    var reservation = try channel.reserveWithToken(producer);
    reservation.abort();
    try testing.expect(channel.journal.peek() == null);
}

test "SPSC retire reactivate invalidates old generation and retains pending data" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const channel = try spsc.SpscJournal.create(testing.allocator, testing.io, try optionsFor(&tmp, &buffer, 3));
    defer channel.deinit();
    const old_token = try channel.token();
    const owner_cookie = channel.control.ownerCookie();
    try append(channel, "old owner data");
    try channel.retire();
    try testing.expectError(error.Retired, channel.reserve());
    try testing.expectError(error.Retired, channel.reserveWithToken(old_token));
    try testing.expect(channel.stats().retired);
    try testing.expectEqual(@as(usize, 1), channel.stats().pending);
    const new_token = try channel.reactivate();
    try testing.expectEqual(owner_cookie, channel.control.ownerCookie());
    try testing.expectEqual(owner_cookie, try spsc.registerCurrentThreadCookie());
    try testing.expectEqual(old_token.generation + 1, new_token.generation);
    try testing.expectError(error.StaleToken, channel.reserveWithToken(old_token));
    try testing.expectError(error.AlreadyActive, channel.reactivate());
    try append(channel, "new owner data");
    try testing.expectEqualStrings("old owner data", (try channel.journal.peekChecked()).?.payload);
    try channel.journal.release((try channel.journal.peekChecked()).?);
    try testing.expectEqualStrings("new owner data", (try channel.journal.peekChecked()).?.payload);
    try channel.journal.release((try channel.journal.peekChecked()).?);
    try testing.expectEqual(@as(u64, 2), channel.stats().reservation_target);
    try testing.expectEqual(@as(usize, 0), channel.stats().pending);
}

test "SPSC retired channel can transfer ownership to another thread" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const channel = try spsc.SpscJournal.create(testing.allocator, testing.io, try optionsFor(&tmp, &buffer, 3));
    defer channel.deinit();
    const original_owner = channel.stats().owner;
    const original_cookie = channel.control.ownerCookie();
    try append(channel, "main thread");
    try channel.retire();
    const Worker = struct {
        fn run(store: *spsc.SpscJournal, success: *bool) void {
            _ = store.reactivate() catch return;
            append(store, "worker thread") catch return;
            store.retire() catch return;
            success.* = true;
        }
    };
    var success = false;
    const worker = try std.Thread.spawn(.{}, Worker.run, .{ channel, &success });
    worker.join();
    try testing.expect(success);
    try testing.expect(channel.stats().owner != original_owner);
    try testing.expect(channel.control.ownerCookie() != original_cookie);
    try testing.expectEqual(@as(u64, 2), channel.stats().generation);
    try testing.expectEqualStrings("main thread", (try channel.journal.peekChecked()).?.payload);
    try channel.journal.release((try channel.journal.peekChecked()).?);
    try testing.expectEqualStrings("worker thread", (try channel.journal.peekChecked()).?.payload);
    try channel.journal.release((try channel.journal.peekChecked()).?);
    _ = try channel.reactivate();
    try testing.expectEqual(original_owner, channel.stats().owner);
    try testing.expectEqual(original_cookie, channel.control.ownerCookie());
    try testing.expectEqual(@as(u64, 3), channel.stats().generation);
}

test "SPSC reopens committed data across reservation gap using same file protocol" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &buffer, 4);
    const first = try spsc.SpscJournal.create(testing.allocator, testing.io, options);
    _ = try first.reserve();
    try append(first, "committed two");
    first.deinit();
    const second = try spsc.SpscJournal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    try testing.expectEqual(@as(u64, 1), second.journal.writtenTarget());
    try append(second, "live three");
    var record = (try second.journal.peekChecked()).?;
    try testing.expectEqual(@as(u64, 2), record.sequence);
    try testing.expectEqualStrings("committed two", record.payload);
    try second.journal.release(record);
    record = (try second.journal.peekChecked()).?;
    try testing.expectEqual(@as(u64, 3), record.sequence);
    try second.journal.release(record);
    try testing.expectEqual(@as(usize, 0), second.stats().pending);
}

test "SPSC reserve commit retire reactivate allocate nothing after creation" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const channel = try spsc.SpscJournal.create(failing.allocator(), testing.io, try optionsFor(&tmp, &buffer, 2));
    defer channel.deinit();
    const allocation_count = failing.alloc_index;
    failing.fail_index = allocation_count;
    for (0..100) |_| {
        try append(channel, "no allocator");
        try channel.journal.release((try channel.journal.peekChecked()).?);
        try channel.retire();
        _ = try channel.reactivate();
    }
    try testing.expectEqual(allocation_count, failing.alloc_index);
}

test "SPSC written durable checkpoint confirms consumer progress without reclaiming pending data" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const options = try optionsFor(&tmp, &buffer, 3);
    const first = try spsc.SpscJournal.create(testing.allocator, testing.io, options);
    try append(first, "written one");
    try append(first, "pending two");
    try first.journal.release((try first.journal.peekChecked()).?);
    try testing.expectEqual(@as(u64, 1), first.journal.writtenTarget());
    try first.journal.checkpointWrittenDurable();
    try testing.expectEqual(@as(u64, 1), first.journal.durableReclaimedTarget());
    try testing.expectEqual(@as(u64, 1), format.get(u64, first.journal.mapping.bytes, 72));
    try testing.expectEqual(@as(usize, 1), first.stats().pending);
    first.deinit();
    const second = try spsc.SpscJournal.create(testing.allocator, testing.io, options);
    defer second.deinit();
    const record = (try second.journal.peekChecked()).?;
    try testing.expectEqual(@as(u64, 2), record.sequence);
    try testing.expectEqualStrings("pending two", record.payload);
    try testing.expectEqual(@as(u64, 1), second.stats().written_target);
    try second.journal.release(record);
    try testing.expectEqual(@as(u64, 2), second.stats().written_target);
}

test "SPSC producer and consumer concurrently wrap cached cursors" {
    if (!@import("../platform/mapping.zig").supported) return error.SkipZigTest;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [128]u8 = undefined;
    const channel = try spsc.SpscJournal.create(testing.allocator, testing.io, try optionsFor(&tmp, &buffer, 8));
    defer channel.deinit();
    const total = 1200;
    const Worker = struct {
        fn run(store: *journal.Journal, stop: *std.atomic.Value(bool), failed: *std.atomic.Value(bool)) void {
            var received: u64 = 0;
            while (received < total) {
                if (stop.load(.acquire)) return;
                const record = (store.peekChecked() catch {
                    failed.store(true, .release);
                    return;
                }) orelse {
                    std.Thread.yield() catch {};
                    continue;
                };
                if (record.sequence != received + 1 or format.get(u64, record.payload, 0) != record.sequence) {
                    failed.store(true, .release);
                    return;
                }
                store.release(record) catch {
                    failed.store(true, .release);
                    return;
                };
                received += 1;
            }
        }
    };
    var stop: std.atomic.Value(bool) = .init(false);
    var failed: std.atomic.Value(bool) = .init(false);
    const consumer = try std.Thread.spawn(.{}, Worker.run, .{ channel.journal, &stop, &failed });
    var joined = false;
    defer if (!joined) {
        stop.store(true, .release);
        consumer.join();
    };
    for (0..total) |_| {
        var reservation = while (true) {
            if (failed.load(.acquire)) return error.ConsumerFailed;
            break channel.reserve() catch |err| switch (err) {
                error.Full => {
                    std.Thread.yield() catch {};
                    continue;
                },
                else => return err,
            };
        };
        format.put(u64, reservation.buffer(), 0, reservation.sequence);
        try reservation.commit(8);
    }
    consumer.join();
    joined = true;
    try testing.expect(!failed.load(.acquire));
    try testing.expectEqual(@as(usize, 0), channel.stats().pending);
    try testing.expect(channel.stats().high_water <= 8);
    try testing.expectEqual(@as(u64, total), channel.stats().written_target);
}
