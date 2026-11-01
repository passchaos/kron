const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len != 2) return error.MissingPattern;
    const repetitions = 1000;
    const started = std.Io.Clock.awake.now(init.io);
    for (0..repetitions) |_| {
        const pattern = try kron.Pattern.init(arguments[1]);
        std.mem.doNotOptimizeAway(&pattern);
    }
    const elapsed = started.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
    std.debug.print("pattern_bytes={d} predicate_bytes={d} compile_attempts={d} compile_batch_ns={d}\n", .{ @sizeOf(kron.Pattern), @sizeOf(kron.Predicate), repetitions, elapsed });
}
