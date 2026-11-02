//! Stack scratch belongs only to submissions with configured redaction rules.
//! The callback completes encoding before this storage goes out of scope.
const field = @import("field.zig");
const Event = @import("event.zig").Event;
const EmitResult = @import("logger.zig").EmitResult;
const Redactor = @import("../pipeline/redact.zig").Redactor;

pub noinline fn submit(owner: anytype, redactor: *const Redactor, original: *const Event, context: anytype, comptime callback: anytype) !EmitResult {
    var fields: [field.max_value_nodes]field.Field = undefined;
    var values: [field.max_value_nodes]field.Value = undefined;
    var arguments: [field.max_value_nodes]field.Field = undefined;
    var argument_values: [field.max_value_nodes]field.Value = undefined;
    var event = original.*;
    event.fields = try redactor.applyDeep(original.fields, &fields, &values);
    event.format_args = try redactor.applyArgumentsDeep(original.format_args, &arguments, &argument_values);
    return callback(owner, &event, context);
}
