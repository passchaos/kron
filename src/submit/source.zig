//! Compile-time mapping from Zig's module-relative source files to project paths.
const std = @import("std");

/// module_directory is the module source root relative to the application
/// repository, such as "src" or "packages/http/src". No filesystem or runtime
/// allocation is involved; module/function/line/column remain the caller's.
pub fn fromModule(comptime module_directory: []const u8, comptime location: std.builtin.SourceLocation) std.builtin.SourceLocation {
    if (comptime module_directory.len != 0 and (module_directory[0] == '/' or module_directory[0] == '\\')) @compileError("source module directory must be repository-relative");
    if (comptime location.file.len != 0 and (location.file[0] == '/' or location.file[0] == '\\')) @compileError("source file must be repository-relative");
    const directory = comptime normalize(module_directory);
    const file = comptime normalize(location.file);
    comptime validateRelative(directory);
    comptime validateRelative(file);
    var result = location;
    result.file = comptime if (directory.len == 0) file ++ "" else directory ++ "/" ++ file;
    return result;
}

fn normalize(comptime input: []const u8) [:0]const u8 {
    return comptime blk: {
        var bytes: [input.len]u8 = undefined;
        for (input, 0..) |byte, index| bytes[index] = if (byte == '\\') '/' else byte;
        var start: usize = 0;
        var end = bytes.len;
        while (end > start and bytes[end - 1] == '/') end -= 1;
        while (end - start >= 2 and bytes[start] == '.' and bytes[start + 1] == '/') start += 2;
        if (end - start == 1 and bytes[start] == '.') start = end;
        const result = bytes[start..end].* ++ "";
        break :blk result;
    };
}

fn validateRelative(comptime path: []const u8) void {
    if (path.len != 0 and path[0] == '/') @compileError("source module directory and file must be repository-relative");
    if (path.len >= 2 and path[1] == ':') @compileError("source module directory and file must be repository-relative");
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..")) @compileError("source paths must remain inside the repository root");
    }
}

test "source paths are mapped at compile time without changing location metadata" {
    const original: std.builtin.SourceLocation = .{ .module = "http", .file = "handlers/request.zig", .fn_name = "serve", .line = 42, .column = 7 };
    const mapped = fromModule("src", original);
    try std.testing.expectEqualStrings("src/handlers/request.zig", mapped.file);
    try std.testing.expectEqual(original.module, mapped.module);
    try std.testing.expectEqual(original.fn_name, mapped.fn_name);
    try std.testing.expectEqual(original.line, mapped.line);
    try std.testing.expectEqual(original.column, mapped.column);
    const windows = fromModule(".\\packages\\http\\src\\", .{ .module = "http", .file = "handlers\\request.zig", .fn_name = "serve", .line = 42, .column = 7 });
    try std.testing.expectEqualStrings("packages/http/src/handlers/request.zig", windows.file);
    try std.testing.expectEqualStrings(original.file, fromModule(".", original).file);
}
