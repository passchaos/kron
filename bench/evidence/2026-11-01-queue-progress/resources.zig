const std = @import("std");
const kron = @import("kron");
pub fn main() void {
    std.debug.print("Journal={d} control={d} control_align={d}\n", .{ @sizeOf(kron.Journal), @sizeOf(@TypeOf(@as(kron.Journal, undefined).single)), @alignOf(@TypeOf(@as(kron.Journal, undefined).single)) });
}
