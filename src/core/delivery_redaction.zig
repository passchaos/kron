//! Scratch exists only for a route with output-specific redaction.
const field = @import("field.zig");
const Event = @import("event.zig").Event;
const Route = @import("runtime_types.zig").Route;

pub noinline fn render(route: *const Route, original: Event, output: []u8, comptime callback: anytype) ![]const u8 {
    var fields: [field.max_value_nodes]field.Field = undefined;
    var values: [field.max_value_nodes]field.Value = undefined;
    var arguments: [field.max_value_nodes]field.Field = undefined;
    var argument_values: [field.max_value_nodes]field.Value = undefined;
    const redactor = route.policy.?.redactor.?;
    var event = original;
    event.fields = try redactor.applyDeep(original.fields, &fields, &values);
    event.format_args = try redactor.applyArgumentsDeep(original.format_args, &arguments, &argument_values);
    event.tree_validated = false;
    return callback(route, output, event);
}
