const std = @import("std");
var x: u64 = 0;
fn worker() void { for (0..100000) |_| x += 1; }
pub fn main(init: std.process.Init) !void {
    _ = init;
    const t1 = try std.Thread.spawn(.{}, worker, .{});
    const t2 = try std.Thread.spawn(.{}, worker, .{});
    t1.join(); t2.join();
    std.debug.print("{d}\n", .{x});
}
