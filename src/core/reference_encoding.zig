//! Internal schema payload encoding. Public schema codec calls measureValues
//! before writing. Runtime may reuse its own measured value bytes only within
//! the same unmodified submission; no measured encoder is exported at root.
const std = @import("std");
const codec = @import("codec.zig");
const schema = @import("../journal/schema.zig");
const Event = @import("event.zig").Event;
const field_module = @import("field.zig");
const Field = field_module.Field;
const SizeVisitor = @import("wire_size.zig").SizeVisitor;
const wire = @import("wire_write.zig");
const Definition = schema.Definition;
const EncodeError = codec.EncodeError || schema.Error || error{SchemaMismatch};
const version = codec.reference_version;

fn validateShape(event: Event, definition: Definition) EncodeError!void {
    if (!std.mem.eql(u8, event.scope, definition.scope) or event.message_template != definition.message_template or !schema.sourceEqual(event.source, definition.source) or event.fields.len != definition.field_count or event.format_args.len != definition.argument_count) return error.SchemaMismatch;
    if (definition.message) |message| if (!std.mem.eql(u8, event.message, message)) return error.SchemaMismatch;
    var fields = definition.fields();
    for (event.fields) |field| {
        const expected = (try fields.next()) orelse return error.SchemaMismatch;
        if (!std.mem.eql(u8, field.key, expected.key) or expected.kind_mask & schema.kindMask(codec.valueTag(field.value)) == 0) return error.SchemaMismatch;
    }
    var arguments = definition.arguments();
    for (event.format_args) |argument| {
        const expected = (try arguments.next()) orelse return error.SchemaMismatch;
        if (!std.mem.eql(u8, argument.key, expected.key) or expected.kind_mask & schema.kindMask(codec.valueTag(argument.value)) == 0) return error.SchemaMismatch;
    }
    if (event.level == .off) return error.InvalidLevel;
}

/// Validates the whole attributes/arguments tree and measures dynamic values
/// plus nested keys. Top-level metadata and level are deliberately not checked
/// here: Runtime's predicate/full-queue ordering must remain unchanged.
pub fn measureValues(event: Event) field_module.ValidationError!u64 {
    var validator: field_module.ValueValidator = .{};
    var visitor: ReferenceSizeVisitor = .{ .size = .{}, .validator = &validator };
    try validator.fieldsWith(event.fields, &visitor);
    try validator.argumentsWith(event.format_args, &visitor);
    return visitor.size.total;
}

/// Internal: values_bytes comes from measureValues on this unchanged event.
/// Shape/level precede the final overflow check, just as in the public codec.
pub fn sizeMeasured(event: Event, definition: Definition, values_bytes: u64) EncodeError!usize {
    try validateShape(event, definition);
    var size: SizeVisitor = .{ .total = values_bytes };
    size.add(codec.header_size);
    if (event.trace_id != null) size.add(16);
    if (event.span_id != null) size.add(8);
    if (definition.message == null) size.blob(event.message.len, false);
    return size.result();
}

const ReferenceSizeVisitor = struct {
    pub const Error = error{};
    size: SizeVisitor,
    validator: *const field_module.ValueValidator,

    pub fn onField(self: *@This(), entry: Field) Error!void {
        // Top-level keys live in the schema. A nested group key remains part
        // of this payload and must be counted, including groups in arguments.
        if (self.validator.depth != 0) try self.size.onField(entry);
    }

    pub fn onValue(self: *@This(), value: field_module.Value) Error!void {
        try self.size.onValue(value);
    }
};

pub fn writeMeasured(event: Event, definition: Definition, values_bytes: u64, destination: []u8) EncodeError![]const u8 {
    const size = try sizeMeasured(event, definition, values_bytes);
    if (destination.len < size) return error.BufferTooSmall;
    var output: wire.FixedOutput = .{ .buffer = destination[0..size] };
    try codec.writeHeaderTo(&output, event, size, version);
    if (event.trace_id) |id| try output.put(&id);
    if (event.span_id) |id| try output.put(&id);
    if (definition.message == null) {
        try output.int(u32, @intCast(event.message.len));
        try output.put(event.message);
    }
    for (event.fields) |field| try wire.writeValueTo(&output, field.value);
    for (event.format_args) |argument| try wire.writeValueTo(&output, argument.value);
    std.debug.assert(output.index == size);
    return destination[0..size];
}
