/// A borrowed, type-erased destination for complete encoded records.
/// Implementations document their thread contract. The built-in sinks have a
/// single owner; a runtime must serialize whole-record calls when sharing one.
/// writeRecord accepts bytes, flush confirms all accepted bytes were written,
/// and sync confirms the destination's durability contract.
pub const Sink = struct {
    context: *anyopaque,
    vtable: *const VTable,
    supports_durable: bool = false,
    /// Stable delivery target used to bind journal recovery to this sink.
    /// Borrowed storage must remain valid and unchanged for the sink lifetime.
    /// null means the sink supplies no automatic recovery target identity.
    recovery_identity: ?[]const u8 = null,

    pub const VTable = struct {
        writeRecord: *const fn (*anyopaque, []const u8) anyerror!void,
        flush: *const fn (*anyopaque) anyerror!void,
        sync: *const fn (*anyopaque) anyerror!void,
    };

    pub fn writeRecord(self: Sink, record: []const u8) !void {
        return self.vtable.writeRecord(self.context, record);
    }

    pub fn flush(self: Sink) !void {
        return self.vtable.flush(self.context);
    }

    pub fn sync(self: Sink) !void {
        if (!self.supports_durable) return error.UnsupportedDurability;
        return self.vtable.sync(self.context);
    }
};
