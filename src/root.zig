//! Public Zig package. Applications begin with Logging; advanced exports
//! remain available for custom output, protocol and runtime integration.
const std = @import("std");

// Application entry and structured events.
pub const Logging = @import("logging/root.zig").Logging;
pub const Level = @import("core/level.zig").Level;
pub const Event = @import("core/event.zig").Event;
pub const Field = @import("core/field.zig").Field;
pub const Value = @import("core/field.zig").Value;
pub const Format = encoder.Format;
pub const EmitResult = @import("core/logger.zig").EmitResult;
pub const fields = @import("core/field.zig");
pub const kv = fields.kv;
pub const secret = fields.secret;
pub const bytes = fields.bytes;
pub const durationNs = fields.durationNs;
pub const timestampNs = fields.timestampNs;
pub const array = fields.array;
pub const group = fields.group;

// Context, selected fields and explicit trace propagation.
pub const OwnedContext = @import("core/context.zig").OwnedContext;
pub const Adapter = @import("core/adapter.zig").Adapter;
pub const MappedAdapter = @import("core/adapter.zig").MappedAdapter;
pub const FieldMap = @import("core/adapter.zig").FieldMap;
pub const object = @import("core/adapter.zig").object;
pub const objectMapped = @import("core/adapter.zig").objectMapped;
pub const TraceContext = @import("telemetry/trace_context.zig").TraceContext;
pub const Span = @import("telemetry/span.zig").Span;

// Application configuration and diagnostics.
pub const Filter = @import("config/filter.zig").Filter;
pub const DynamicFilter = @import("config/reload.zig").DynamicFilter;
pub const FilterDecision = @import("config/reload.zig").Decision;
pub const CachedFilter = @import("config/cache.zig").CachedFilter;
pub const environment = @import("config/env.zig");
pub const configuration_sources = @import("config/sources.zig");
pub const configuration_document = @import("config/document.zig");
pub const Sampler = @import("pipeline/sampler.zig").Sampler;
pub const Redactor = @import("pipeline/redact.zig").Redactor;
pub const Predicate = @import("pipeline/predicate.zig").Predicate;
pub const Pattern = @import("pipeline/predicate.zig").Pattern;
pub const diagnostics = @import("core/diagnostics.zig");
pub const std_log = @import("adapters/std_log.zig");

// Advanced runtime, output resources and completion controls.
pub const Runtime = @import("core/runtime.zig").Runtime;
pub const RuntimeOptions = @import("core/runtime.zig").Options;
pub const MemoryQueueOptions = @import("core/runtime_types.zig").MemoryQueueOptions;
pub const QueueStorage = @import("core/runtime_types.zig").QueueStorage;
pub const RouteOptions = @import("core/runtime.zig").RouteOptions;
pub const Configuration = @import("core/runtime.zig").Configuration;
pub const ConfigurationVersion = @import("core/runtime.zig").ConfigurationVersion;
pub const Deadline = @import("core/control.zig").Deadline;
pub const Sink = @import("sink/interface.zig").Sink;
pub const MemorySink = @import("sink/memory.zig").MemorySink;
pub const FileSink = @import("sink/file.zig").FileSink;
pub const WriterSink = @import("sink/writer.zig").WriterSink;
pub const MultiSink = @import("sink/multi.zig").MultiSink;
pub const RollingFileSink = @import("sink/rolling_file.zig").RollingFileSink;
pub const CompressedArchiveSink = @import("sink/compressed_archive.zig").CompressedArchiveSink;
pub const FlightRecorder = @import("pipeline/flight_recorder.zig").FlightRecorder;

// Encoding, persistent protocols and prepared metadata.
pub const encoder = @import("encoder/root.zig");
pub const codec = @import("core/codec.zig");
pub const schema_codec = @import("core/schema_codec.zig");
pub const schema = @import("journal/schema.zig");
pub const SchemaBinding = @import("core/prepared.zig").Binding;
pub const Journal = @import("journal/journal.zig").Journal;
pub const SpscJournal = @import("journal/spsc.zig").SpscJournal;
pub const archive = @import("archive/reader.zig");
pub const compression = @import("archive/compression.zig");
pub const format = @import("submit/format.zig");
pub const callsite = @import("submit/callsite.zig");
pub const source = @import("submit/source.zig");
pub const schema_site = @import("submit/schema_site.zig");

// Time and platform providers.
pub const time = @import("time/root.zig");
pub const platform = @import("platform/capabilities.zig");
pub const Clock = @import("platform/clock.zig").Clock;
pub const StandardClock = @import("platform/static_clock.zig").StandardClock;
pub const NativeClock = @import("platform/static_clock.zig").NativeClock;
pub const ZeroClock = @import("platform/static_clock.zig").ZeroClock;
pub const TscClock = @import("platform/tsc_clock.zig").TscClock;

test {
    std.testing.refAllDecls(@This());
    _ = @import("core/level.zig");
    _ = @import("core/admission.zig");
    _ = @import("encoder/escaping.zig");
    _ = @import("platform/crc32.zig");
    const test_cpu = @import("builtin").cpu;
    if (test_cpu.arch == .x86_64 and
        std.Target.x86.featureSetHas(test_cpu.features, .pclmul) and
        std.Target.x86.featureSetHas(test_cpu.features, .sse2))
    {
        _ = @import("platform/crc32_pclmul.zig");
    }
}
