const std = @import("std");
const kron = @import("kron");

pub const Mode = enum { sync, asynchronous, spsc };
pub const QueueStorage = enum { mmap, memory };
pub const Sink = enum { memory, file };
pub const Backend = enum { auto, portable, linux_uring };
pub const Payload = enum { numeric, short, long };
pub const Temperature = enum { warm, cold };
pub const Format = enum { json, text, logfmt };
pub const Output = enum { json, csv };
pub const Overflow = enum { block, drop_newest };
pub const Idle = enum { auto, sleep, spin };
pub const Clock = enum { dynamic, std_io, native, none };

/// Total events, samples, warmup events and memory are process-wide budgets.
/// Borrowed argument strings stay valid until the executable finishes.
pub const Options = struct {
    mode: Mode = .sync,
    storage: QueueStorage = .mmap,
    sink: Sink = .memory,
    backend: Backend = .portable,
    events: usize = 10_000,
    producers: usize = 1,
    fields: usize = 5,
    payload: Payload = .numeric,
    string_bytes: usize = 256,
    filtered: bool = false,
    no_verify_crc: bool = false,
    temperature: Temperature = .warm,
    warmup_events: usize = 1_000,
    samples: usize = 10_000,
    format: Format = .json,
    output: Output = .json,
    overflow: Overflow = .block,
    memory_bytes: usize = 64 * 1024 * 1024,
    journal_slots: usize = 256,
    channel_slots: usize = 256,
    journal_bytes: usize = 256 * 1024 * 1024,
    idle: Idle = .auto,
    clock: Clock = .dynamic,
    schema: bool = false,
    max_record_bytes: usize = 16 * 1024,
    buffer_bytes: usize = 64 * 1024,
    queue_depth: u16 = 4,
    work_dir: []const u8 = ".zig-cache/kron-bench",
    durable: bool = false,
    help: bool = false,

    pub fn modeName(self: Options) []const u8 {
        return if (self.mode == .asynchronous) "async" else @tagName(self.mode);
    }

    pub fn storageName(self: Options) []const u8 {
        return if (self.mode == .sync) "none" else @tagName(self.storage);
    }

    pub fn validate(self: Options) !void {
        if (self.mode == .sync and self.storage == .memory) return error.InvalidConfiguration;
        if (self.no_verify_crc and (self.mode == .sync or self.storage != .memory)) return error.InvalidConfiguration;
        if (self.schema and (self.mode == .sync or self.clock != .dynamic)) return error.InvalidConfiguration;
        if (self.events == 0 or self.events > 10_000_000) return error.InvalidEventBudget;
        if (self.producers != 1 and self.producers != 4 and self.producers != 16) return error.InvalidProducerCount;
        if (self.fields != 0 and self.fields != 5 and self.fields != 10) return error.InvalidFieldCount;
        if (self.samples == 0 or self.samples > 1_000_000 or self.warmup_events > 1_000_000) return error.InvalidSampleBudget;
        if (self.string_bytes == 0 or self.string_bytes > 16 * 1024) return error.InvalidStringBudget;
        if (self.memory_bytes == 0 or self.memory_bytes > 2 * 1024 * 1024 * 1024) return error.InvalidMemoryBudget;
        if (self.journal_slots < 2 or self.journal_slots > 1_048_576 or !std.math.isPowerOfTwo(self.journal_slots)) return error.InvalidJournalBudget;
        if (self.max_record_bytes < 512 or self.max_record_bytes > 1024 * 1024) return error.InvalidRecordBudget;
        if (self.channel_slots < 2 or self.channel_slots > 1_048_576 or !std.math.isPowerOfTwo(self.channel_slots)) return error.InvalidJournalBudget;
        if (self.journal_bytes == 0 or self.journal_bytes > 512 * 1024 * 1024 or try self.journalAllocationBytes() > self.journal_bytes) return error.InvalidJournalBudget;
        if (self.buffer_bytes < self.max_record_bytes or self.buffer_bytes > 16 * 1024 * 1024) return error.InvalidBufferBudget;
        if (self.queue_depth == 0 or self.queue_depth > 256 or !std.math.isPowerOfTwo(self.queue_depth)) return error.InvalidQueueDepth;
        if (self.work_dir.len == 0) return error.InvalidWorkDirectory;
        if (self.sink == .memory and self.backend != .portable) return error.FileBackendRequiresFileSink;
        if (self.durable and self.sink != .file) return error.DurabilityRequiresFileSink;
        if (self.temperature == .warm and self.warmup_events == 0) return error.WarmupRequired;
    }

    /// Total queue storage budget for either mapped or memory-backed journals:
    /// 4096-byte header, fixed aligned slots and optional prepared metadata.
    /// Runtime independently enforces the same complete allocation budget.
    pub fn journalAllocationBytes(self: Options) !usize {
        if (self.mode == .sync) return 0;
        const stride = std.mem.alignForward(usize, self.max_record_bytes + 64, 64);
        const main_base = std.math.add(usize, 4096, std.math.mul(usize, self.journal_slots, stride) catch return error.InvalidJournalBudget) catch return error.InvalidJournalBudget;
        const main = if (self.schema) (try kron.schema.layout(main_base, 2, 4096)).size else main_base;
        if (self.mode != .spsc) return main;
        const channel_base = std.math.add(usize, 4096, std.math.mul(usize, self.channel_slots, stride) catch return error.InvalidJournalBudget) catch return error.InvalidJournalBudget;
        const channel = if (self.schema) (try kron.schema.layout(channel_base, 2, 4096)).size else channel_base;
        return std.math.add(usize, main, std.math.mul(usize, channel, self.producers) catch return error.InvalidJournalBudget) catch return error.InvalidJournalBudget;
    }
};

pub const usage =
    \\Usage: kron-bench [--KEY=VALUE | --KEY VALUE] [--filtered] [--durable]
    \\Runs independent sampled-latency and batch-average trials with final drain.
    \\  --mode sync|async|spsc          Default sync; spsc attaches each producer.
    \\  --storage mmap|memory          Queue storage; default mmap; sync reports none.
    \\  --sink memory|file             Default memory.
    \\  --backend portable|auto|linux_uring  File backend; default portable.
    \\  --events N                     Total attempts per trial; default 10000.
    \\  --producers 1|4|16              Default 1; events split across producers.
    \\  --fields 0|5|10                Default 5 typed attributes.
    \\  --payload numeric|short|long    Default numeric.
    \\  --string-bytes N               Long message/attribute size; default 256.
    \\  --temperature warm|cold        Default warm; cold means no emit warmup.
    \\  --warmup-events N              Total excluded warmup attempts; default 1000.
    \\  --samples N                    Maximum latency samples; default 10000.
    \\  --format json|text|logfmt       Encoder output; default json.
    \\  --output json|csv              Benchmark report; default JSON Lines.
    \\  --overflow block|drop_newest    Journal overload policy; default block.
    \\  --memory-bytes N               Memory sink budget; default 67108864.
    \\  --journal-slots N              Power of two; default 256.
    \\  --channel-slots N              Per SPSC channel capacity; default 256.
    \\  --journal-bytes N              Total shared + SPSC budget; default 268435456.
    \\  --idle auto|sleep|spin          Auto uses runtime defaults.
    \\  --clock dynamic|std_io|native|none  Event timestamp path; default dynamic.
    \\  --schema                       Prepared metadata v2; async/SPSC + dynamic clock.
    \\  --no-verify-crc                Memory-only opt-out: skip slot CRC write/validation.
    \\  --max-record-bytes N           Journal/runtime record bound; default 16384.
    \\  --buffer-bytes N               File staging/batch budget; default 65536.
    \\  --queue-depth N                Power of two, <=256; default 4.
    \\  --work-dir PATH                Default .zig-cache/kron-bench; keeps artifacts.
    \\  --filtered                     Emit info while runtime filter is off.
    \\  --durable                      Time an additional final durable flush.
    \\  --help, -h                     Show this help.
    \\All sizes are decimal bytes. Unknown or incompatible arguments are errors.
    \\
;

pub fn parse(arguments: []const []const u8) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        if (std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h")) {
            options.help = true;
            continue;
        }
        if (std.mem.eql(u8, argument, "--filtered")) {
            options.filtered = true;
            continue;
        }
        if (std.mem.eql(u8, argument, "--durable")) {
            options.durable = true;
            continue;
        }
        if (std.mem.eql(u8, argument, "--schema")) {
            options.schema = true;
            continue;
        }
        if (std.mem.eql(u8, argument, "--no-verify-crc")) {
            options.no_verify_crc = true;
            continue;
        }
        if (!std.mem.startsWith(u8, argument, "--")) return error.UnknownArgument;
        const pair = argument[2..];
        const equal = std.mem.indexOfScalar(u8, pair, '=');
        const key = if (equal) |position| pair[0..position] else pair;
        const value = if (equal) |position| pair[position + 1 ..] else blk: {
            index += 1;
            if (index >= arguments.len or std.mem.startsWith(u8, arguments[index], "--")) return error.MissingOptionValue;
            break :blk arguments[index];
        };
        if (value.len == 0) return error.MissingOptionValue;
        if (std.mem.eql(u8, key, "mode")) {
            options.mode = if (std.mem.eql(u8, value, "async")) .asynchronous else std.meta.stringToEnum(Mode, value) orelse return error.InvalidMode;
        } else if (std.mem.eql(u8, key, "storage")) {
            options.storage = try enumeration(QueueStorage, value);
        } else if (std.mem.eql(u8, key, "sink")) {
            options.sink = try enumeration(Sink, value);
        } else if (std.mem.eql(u8, key, "backend")) {
            options.backend = try enumeration(Backend, value);
        } else if (std.mem.eql(u8, key, "payload")) {
            options.payload = try enumeration(Payload, value);
        } else if (std.mem.eql(u8, key, "temperature")) {
            options.temperature = try enumeration(Temperature, value);
        } else if (std.mem.eql(u8, key, "format")) {
            options.format = try enumeration(Format, value);
        } else if (std.mem.eql(u8, key, "output")) {
            options.output = try enumeration(Output, value);
        } else if (std.mem.eql(u8, key, "overflow")) {
            options.overflow = try enumeration(Overflow, value);
        } else if (std.mem.eql(u8, key, "idle")) {
            options.idle = try enumeration(Idle, value);
        } else if (std.mem.eql(u8, key, "clock")) {
            options.clock = try enumeration(Clock, value);
        } else if (std.mem.eql(u8, key, "work-dir")) {
            options.work_dir = value;
        } else if (std.mem.eql(u8, key, "queue-depth")) {
            options.queue_depth = try std.fmt.parseInt(u16, value, 10);
        } else {
            const integer = std.fmt.parseInt(usize, value, 10) catch return error.InvalidInteger;
            if (std.mem.eql(u8, key, "events")) {
                options.events = integer;
            } else if (std.mem.eql(u8, key, "producers")) {
                options.producers = integer;
            } else if (std.mem.eql(u8, key, "fields")) {
                options.fields = integer;
            } else if (std.mem.eql(u8, key, "string-bytes")) {
                options.string_bytes = integer;
            } else if (std.mem.eql(u8, key, "warmup-events")) {
                options.warmup_events = integer;
            } else if (std.mem.eql(u8, key, "samples")) {
                options.samples = integer;
            } else if (std.mem.eql(u8, key, "memory-bytes")) {
                options.memory_bytes = integer;
            } else if (std.mem.eql(u8, key, "journal-slots")) {
                options.journal_slots = integer;
            } else if (std.mem.eql(u8, key, "channel-slots")) {
                options.channel_slots = integer;
            } else if (std.mem.eql(u8, key, "journal-bytes")) {
                options.journal_bytes = integer;
            } else if (std.mem.eql(u8, key, "max-record-bytes")) {
                options.max_record_bytes = integer;
            } else if (std.mem.eql(u8, key, "buffer-bytes")) {
                options.buffer_bytes = integer;
            } else return error.UnknownArgument;
        }
    }
    if (!options.help) try options.validate();
    return options;
}

fn enumeration(comptime T: type, value: []const u8) !T {
    return std.meta.stringToEnum(T, value) orelse error.InvalidOptionValue;
}

test "benchmark arguments preserve total budgets and explicit backend" {
    const options = try parse(&.{ "--mode=async", "--sink", "file", "--backend=linux_uring", "--producers=16", "--events=123", "--fields=10", "--payload=long", "--output=csv", "--filtered", "--durable", "--journal-slots=64" });
    try std.testing.expectEqual(Mode.asynchronous, options.mode);
    try std.testing.expectEqual(Backend.linux_uring, options.backend);
    try std.testing.expectEqual(@as(usize, 123), options.events);
    try std.testing.expectEqual(@as(usize, 16), options.producers);
    try std.testing.expectEqual(Output.csv, options.output);
    try std.testing.expect(options.filtered and options.durable);
}

test "benchmark arguments reject ambiguous incompatible and unbounded input" {
    try std.testing.expectError(error.MissingOptionValue, parse(&.{"--events"}));
    try std.testing.expectError(error.InvalidProducerCount, parse(&.{"--producers=3"}));
    try std.testing.expectError(error.InvalidFieldCount, parse(&.{"--fields=6"}));
    try std.testing.expectError(error.InvalidEventBudget, parse(&.{"--events=10000001"}));
    try std.testing.expectError(error.InvalidQueueDepth, parse(&.{"--queue-depth=3"}));
    try std.testing.expectError(error.InvalidJournalBudget, parse(&.{"--journal-slots=15"}));
    try std.testing.expectError(error.InvalidJournalBudget, parse(&.{ "--mode=spsc", "--producers=16", "--journal-bytes=1024" }));
    try std.testing.expectError(error.FileBackendRequiresFileSink, parse(&.{"--backend=linux_uring"}));
    try std.testing.expectError(error.DurabilityRequiresFileSink, parse(&.{"--durable"}));
    try std.testing.expectError(error.WarmupRequired, parse(&.{"--warmup-events=0"}));
    const spsc = try parse(&.{"--mode=spsc"});
    try std.testing.expectEqual(Mode.spsc, spsc.mode);
    try std.testing.expectEqual(@as(usize, 8_429_568), try spsc.journalAllocationBytes());
    const static_clock = try parse(&.{ "--clock=std_io", "--mode=spsc" });
    try std.testing.expectEqual(Clock.std_io, static_clock.clock);
    try std.testing.expectError(error.InvalidOptionValue, parse(&.{"--clock=virtual"}));
    try std.testing.expectError(error.InvalidConfiguration, parse(&.{"--schema"}));
    try std.testing.expectError(error.InvalidConfiguration, parse(&.{ "--schema", "--mode=async", "--clock=std_io" }));
    const schema = try parse(&.{ "--schema", "--mode=spsc" });
    try std.testing.expect(schema.schema);
    try std.testing.expectEqual(@as(usize, 8_446_208), try schema.journalAllocationBytes());
}

test "benchmark queue storage defaults to mmap and memory keeps total schema budgets" {
    const sync = try parse(&.{});
    try std.testing.expectEqual(QueueStorage.mmap, sync.storage);
    try std.testing.expectEqualStrings("none", sync.storageName());
    try std.testing.expectEqual(@as(usize, 0), try sync.journalAllocationBytes());
    try std.testing.expectError(error.InvalidConfiguration, parse(&.{"--storage=memory"}));
    try std.testing.expectError(error.InvalidOptionValue, parse(&.{"--storage=tmpfs"}));
    const memory = try parse(&.{ "--mode=async", "--storage=memory", "--schema", "--sink=file", "--durable" });
    const mapped = try parse(&.{ "--mode=async", "--storage=mmap", "--schema", "--sink=file", "--durable" });
    try std.testing.expectEqualStrings("memory", memory.storageName());
    try std.testing.expectEqual(try mapped.journalAllocationBytes(), try memory.journalAllocationBytes());
    const channels = try parse(&.{ "--mode=spsc", "--storage=memory", "--schema", "--producers=4" });
    try std.testing.expectEqual(@as(usize, 21_115_520), try channels.journalAllocationBytes());
    try std.testing.expectError(error.InvalidJournalBudget, parse(&.{ "--mode=spsc", "--storage=memory", "--schema", "--producers=4", "--journal-bytes=10000" }));
}
