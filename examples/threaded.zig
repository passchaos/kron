const std = @import("std");
const kron = @import("kron");

const Worker = struct {
    logging: *kron.Logging,
    index: u32,
    failure: ?anyerror = null,

    fn run(self: *Worker) void {
        self.work() catch |err| {
            self.failure = err;
        };
    }

    fn work(self: *Worker) !void {
        const log = try self.logging.attachThread("worker");
        defer log.detach() catch {};
        for (0..20) |sequence| {
            _ = try log.tryEmit(.info, "work completed", .{ .worker = self.index, .sequence = @as(u64, @intCast(sequence)) });
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .name = "file",
                .target = .{
                    .file = .{
                        .path = "kron-threaded.jsonl",
                        .backend = .portable,
                    },
                },
                .format = .json,
                .mode = .spsc,
                .max_threads = 2,
            },
        },
    });
    defer logging.destroy();
    var first: Worker = .{ .logging = logging, .index = 0 };
    var second: Worker = .{ .logging = logging, .index = 1 };
    {
        const thread_a = try std.Thread.spawn(.{}, Worker.run, .{&first});
        defer thread_a.join();
        const thread_b = try std.Thread.spawn(.{}, Worker.run, .{&second});
        defer thread_b.join();
    }
    if (first.failure) |err| return err;
    if (second.failure) |err| return err;
    try logging.shutdown();
    if (logging.health().written != 40) return error.IncompleteDelivery;
}
