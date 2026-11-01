const std = @import("std");
const kron = @import("kron");

pub fn main() void {
    const Returned = @typeInfo(@TypeOf(kron.Journal.peekChecked)).@"fn".return_type.?;
    const Record = @typeInfo(@typeInfo(Returned).error_union.payload).optional.child;
    const per_record = @sizeOf(Record) + @sizeOf(u32) + @sizeOf(*anyopaque) + @sizeOf(u8);
    std.debug.print("record_descriptor_bytes={d} four_tracking_arrays_before={d} four_tracking_arrays_after={d} added_bytes={d}\n", .{
        @sizeOf(Record), per_record * 64, per_record * 256, per_record * 192,
    });
}
