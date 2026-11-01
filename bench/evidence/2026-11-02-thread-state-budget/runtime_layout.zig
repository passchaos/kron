const std = @import("std");
const Runtime = @import("kron").Runtime;
pub fn main() void {
    std.debug.print("Runtime size={d} align={d}\n", .{ @sizeOf(Runtime), @alignOf(Runtime) });
    inline for (@typeInfo(Runtime).@"struct".fields) |field| {
        std.debug.print("{s} offset={d} size={d} align={d}\n", .{ field.name, @offsetOf(Runtime, field.name), @sizeOf(field.type), field.alignment orelse @alignOf(field.type) });
    }
    const Counters = @TypeOf(@as(Runtime, undefined).counters);
    std.debug.print("Counters size={d} align={d}\n", .{ @sizeOf(Counters), @alignOf(Counters) });
    inline for (@typeInfo(Counters).@"struct".fields) |field| {
        std.debug.print("counter.{s} offset={d}\n", .{ field.name, @offsetOf(Counters, field.name) });
    }
}
