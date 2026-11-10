# kron usage guide

Applications integrate through `kron.Logging.create`. One `Logging` instance
manages every output in its `outputs` list. Each route owns its mode, queue,
filtering, sampling, redaction, file resources, and delivery state. `scoped`
returns a logger that dispatches to those outputs. The default list is
`&.{.{}}`: one synchronous text output named `stderr` with an info threshold.

This guide targets Zig 0.16. See [package consumption](package.md) for dependency
declarations and build configuration, and [API architecture](api-design.md) for
internal responsibilities and the tracing design mapping.

## Minimal program

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    const log = logging.scoped("app");
    log.info("started", .{ .version = "1.0" });
    _ = try log.tryLogfAt(@src(), .warn, "request {d} completed", .{@as(u32, 42)}, .{ .elapsed = kron.durationNs(1200) });
    try logging.shutdown();
}
```

`log.info/debug/warn/err/fatal/trace` report errors through diagnostics. Use
`tryEmit`, `tryLogf`, or the source-location variants `tryEmitAt` and
`tryLogfAt` when the application must handle errors. An ordinary logger is a
borrowed value and does not need to be destroyed. Stop all users before shutting
down `Logging`, then destroy the owner, and finally clean up the application I/O
environment.

## One file and multiple outputs

A single file is also a one-element list:

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{
            .name = "file",
            .target = .{
                .file = .{
                    .path = "app.jsonl",
                    .backend = .portable,
                },
            },
            .mode = .asynchronous,
            .format = .json,
            .redaction = &.{
                .{
                    .key = "password",
                    .action = .mask,
                },
            },
        },
    },
});
defer logging.destroy();
logging.scoped("http").info("completed", .{ .status = @as(u16, 200) });
try logging.shutdown();
```

Asynchronous mode uses a bounded Memory queue when no queue is configured. Files
are appended by default and the parent directory must already exist. Relative
paths are resolved against the current working directory; `target.file.dir`
accepts an already-open directory. `Logging` owns file and rotating-file
resources; a `FileSink` owns any parent-directory handle it opens.

Add a route for each additional output. The following file route uses SPSC/Mmap
to retain every event, while stdout uses shared Memory, keeps every second
event, and may drop on a full queue. Both use local time:

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{
            .name = "file",
            .target = .{
                .file = .{
                    .path = "app.jsonl",
                    .backend = .portable,
                },
            },
            .mode = .spsc,
            .max_threads = 4,
            .queue = .{
                .mmap = .{
                    .path = "app.journal",
                    .capacity = 256,
                    .max_record_bytes = 8192,
                },
            },
            .overflow = .block,
            .format = .json,
            .sampling = .none,
            .timestamp = .{
                .zone = .local,
            },
            .filter = "info",
            .redaction = &.{
                .{
                    .key = "access_token",
                    .action = .mask,
                },
            },
        },
        .{
            .name = "stdout",
            .target = .stdout,
            .mode = .asynchronous,
            .queue = .{
                .memory = .{
                    .capacity = 64,
                    .max_record_bytes = 4096,
                },
            },
            .overflow = .drop_newest,
            .format = .text,
            .sampling = .{
                .every = 2,
            },
            .delivery = .best_effort,
            .timestamp = .{
                .zone = .local,
            },
            .filter = "info",
            .redaction = &.{
                .{
                    .key = "access_token",
                    .action = .mask,
                },
            },
        },
    },
});
```

Mode, capacity, full-queue policy, filtering, sampling, and redaction all belong
to the individual route. Each call constructs the typed field description and
timestamp once; every pipeline independently decides, redacts, copies, encodes,
and delivers. A single call can be accepted by the file output while being
sampled or dropped by stdout. A `block` route or a slow synchronous output still
extends the call. To reduce producer waiting on a low-priority output, use an
asynchronous queue and `drop_newest`. `best_effort` controls error propagation;
it does not change the waiting policy.

## Route configuration and defaults

`Logging.Options` has only two fields: `outputs` (default `&.{.{}}`) and
`max_total_queue_bytes` (default 256 MiB). Mode, queue, filtering, and output
policies are set directly on each `Logging.Route`; omitted fields take that
route type's defaults.

The default list contains one synchronous text output named `stderr` with an
info filter. Multiple outputs are configured separately.

| Route field | Default | Meaning |
| --- | --- | --- |
| `mode` | `.sync` | `.sync`, `.asynchronous`, or `.spsc` |
| `queue` | null | Sync implies `.none`; asynchronous implies Memory; Memory/Mmap may be explicit |
| `overflow` | `.block` | `.block`, `.drop_newest`, `.fallback_sync` |
| `format` | `.text` | `.text`, `.json`, `.logfmt`, `.binary` |
| `timestamp` | null | Optional readable UTC/fixed-offset/local date |
| `filter` | `"info"` | Default and scope-level thresholds |
| `min_level` | null | Additional minimum-level restriction |
| `sampling` | `.none` | none/count/every/token_bucket |
| `sample_bypass` | `.warn` | This level and above bypass sampling, subject to filtering and predicates |
| `redaction` | empty rules | Recursive redaction before each queue accepts the value |
| `predicate` | null | Acceptance condition based on event fields |
| `delivery` | `.required` | required propagates failures; best_effort records and continues |
| `reclaim_after` | `.written` | Reclaim queue records after written or durable |
| `max_threads` | 4 | Maximum attached threads for SPSC |
| `max_encoded_record_bytes` | 64 KiB | Scratch limit for a complete output record on this pipeline |
| `max_journal_bytes` | 256 MiB | Backing limit for all queues on this pipeline |
| `consumer_batches_per_queue` | 4 | Batches consumed per queue per round, range 1..4 |
| `diagnostics` | `.{}` | Error hook and context for this output |

`name` defaults to `"stderr"` and `target` defaults to `.stderr`; both are set
only on a route. Give multiple routes explicit names. The target supports
`.stderr`, `.stdout`, `.writer`, `.file`, and `.rolling_file`; it describes the
physical destination, while the list expresses one or many outputs.

`redaction = &.{}` means no rules, `sampling = .none` means no sampling, and
`timestamp = null` plus `predicate = null` means no readable time or field
condition. `queue = null` is resolved from the mode: sync uses none, while
asynchronous/SPSC use Memory. Explicitly configuring a queue for sync is an
error. Multiple Mmap routes must use distinct journal paths.

The default Memory parameters are capacity 256, max_record_bytes 8192,
schema_capacity 0, and max_schema_bytes 8192. Each SPSC pipeline also retains an
ordinary shared queue, so the total queue count is `max_threads + 1`. The total
queue budget excludes file staging, Runtime configuration metadata, output
scratch, and logger context.

`FileSink.Options` includes `path`, `dir`, `buffer_bytes = 64 KiB`,
`backend = .portable`, `queue_depth = 4`, and `append = true`. Linux may
explicitly select `.linux_uring` or `.auto`; the portable backend is the measured
default for deferred-consumer batched writes. See
[file reliability](file-reliability.md). The examples in this guide use
portable.

Creation failure releases acquired memory, handles, and Runtime state. Invalid
policies and queue budgets are checked before opening outputs; for a valid
configuration, later OOM or I/O failures do not restore files that were already
created or truncated.

## Methods and results

| Method | Purpose |
| --- | --- |
| `scoped(scope)` | Obtain an allocation-free logger that dispatches to all outputs |
| `scopedOutput(name, scope)` | Direct logger that submits only to the named output; useful in hot loops |
| `attachThread(scope)` | Obtain this thread's channel for every SPSC output; other outputs continue on the ordinary path |
| `prepared(shape)` | Pre-register a shape for all asynchronous pipelines; synchronous outputs use ordinary capture |
| `attachPreparedThread(shape)` | Attach and register the shape for the corresponding thread channels |
| `reloadFilter(spec)` / `setLevel(level)` | Sequentially update filtering for all outputs |
| `reloadOutputFilter(name, spec)` | Update filtering for one output |
| `reloadFilterFile(path)` | Read and apply filter updates for outputs sequentially |
| `flush()` / `flushDurable()` | Confirm written/durable for all applicable outputs |
| `flushOutputs(names)` / `flushOutputsDurable(names)` | Confirm named outputs; errors from explicitly selected outputs propagate |
| `flushUntil(deadline)` / `flushDurableUntil(deadline)` | Confirm outputs using one absolute deadline |
| `shutdown()` / `shutdownUntil(deadline)` | Close admission on all pipelines, then drain sequentially |
| `health()` / `outputHealth(name)` | Aggregate or per-output status |
| `lastResults()` | Per-output results of this OS thread's most recent dispatch, in `outputs` order |
| `runtime(name)` | Borrow the advanced Runtime for a named output; `Logging` owns its lifetime |
| `bindStdLog()` / `unbindStdLog()` | Bind or unbind the standard logging bridge |
| `destroy()` | Release all owned resources after all users have stopped |

`tryEmit`/`tryLogf` return:

| Result | Meaning |
| --- | --- |
| `.accepted` | At least one output accepted; flush/shutdown is still required to confirm background completion |
| `.filtered` | Rejected by a condition/level, or only best_effort outputs failed and none accepted |
| `.sampled` | Rejected by sampling |
| `.dropped_full` / `.dropped_oversize` | Dropped because the queue was full or the record was too large |
| `.rejected_closing` | Admission is closed, or the thread token/reentrancy check rejected the call |
| Error | Capture failed or a required output failed; other outputs may still have succeeded |

Submissions to multiple outputs are not a rollback transaction. On a required
error, other already-admitted outputs are still attempted, then the error is
returned. Inspect `lastResults()` for partial success instead of retrying
blindly and duplicating records. Each element is either `.result: EmitResult` or
`.err: anyerror`; the returned slice is borrowed until the next dispatch on the
same thread, so copy it if it must be retained. Lazy providers are not invoked
when every output filters or samples the event before capture. Recursive logging
is rejected; bounded nested independent `Logging` instances are allowed (up to
8 levels, and at most 64 Runtime admissions in total).

Aggregate health counts accepted/written and similar values per output
submission, so one event written to two places counts twice; queue sizes are
summed across channels, and mixed storage is reported as `.mixed`. This is
observational state, not a transactional snapshot of every atomic value.
Asynchronous `.accepted` only means the record was copied and accepted; later
sink failures are reported through output health, diagnostics, and
flush/shutdown, and cannot be predicted from the call result.

## Fields and format strings

```zig
log.info("completed", .{
    .status = @as(u16, 200),
    .cached = true,
    .elapsed = kron.durationNs(1200),
});
_ = try log.tryLogf(.info, "request {d}: {s}", .{ @as(u64, 42), "done" }, .{});
```

Typed format strings are validated at compile time, and the asynchronous
consumer performs final formatting. Ordinary fields support scalars, optionals,
strings, bytes, explicit arrays/groups, and similar values; arbitrary objects
must select fields explicitly. See [field capture](capture.md),
[structured values](structured-values.md), and
[structured.zig](../examples/structured.zig).

```zig
const fields = [_]kron.Field{
    kron.kv("password", kron.secret("never captured")),
    kron.kv("body", kron.bytes(&payload)),
    kron.kv("nested", kron.group(&nested_fields)),
};
_ = try log.tryEmit(.info, "structured", @as([]const kron.Field, &fields));
```

A top-level event has at most 64 fields. Attributes and format arguments share a
budget of 8 container levels and 256 value nodes; cycles, duplicate group keys,
excessive depth, and oversized records are rejected. A `Secret` value never
enters capture. Redaction keys match the complete field name exactly and apply
recursively to groups; dots do not express a nested path. Each route applies its
rules before copying the value into that route's queue, without modifying caller
data or other outputs.

A custom `{f}` formatter may explicitly use
`tryLogfPreencoded(level, buffer, fmt, args, fields)`; the application supplies
the byte budget and formats on the producer. Ordinary typed deferred formatting
does not borrow the formatter for background use.

Function arguments are evaluated before the call. Guard expensive fields with
`enabled()` or put the work inside a lazy provider's `fields()`:

```zig
const Details = struct {
    calls: *usize,
    pub fn fields(self: @This()) struct { answer: u32 } {
        self.calls.* += 1;
        return .{ .answer = 42 };
    }
};
var calls: usize = 0;
_ = try log.tryEmitLazy(.debug, "details", Details{ .calls = &calls });
```

`enabled()` checks filtering without consuming a sampling slot; it does not
guarantee that the next submission will be accepted.

## Context, filtering, and threads

```zig
const service = logging.scoped("http").withBorrowed(.{ .service = "api" });
const request = service.withBorrowed(.{ .request_id = "req-42", .status = @as(u16, 0) });
request.info("completed", .{ .status = @as(u16, 200) });
```

Fields merge in parent < child < event order. `withBorrowed` does not allocate;
slice/container storage must cover every use of the child. An ordinary scope is
also borrowed bytes. `withOwned` deep-copies the complete merged context at
creation, so emit does not allocate; the application destroys the context once
after all derived values are no longer used.

```zig
var owned = try log.withOwned(allocator, .{ .user = @as([]const u8, &name) });
defer owned.destroy();
```

The message and dynamic values are copied before asynchronous acceptance
succeeds, so the event source buffer may be overwritten after the call returns.
Borrowed writer objects, buffers, and `diagnostics.context` must remain alive
until `Logging.destroy` returns.

```zig
try logging.reloadFilter("info,http=debug,db.query=trace,noisy=off");
try logging.reloadOutputFilter("stdout", "warn");
try logging.setLevel(.warn);
```

Scope rules override the default threshold, and child scopes use the most
specific match. `setLevel` changes only the default while preserving scope
overrides; use `reloadFilter("off")` to disable everything. Sampling quotas are
shared by all producers on each route, and filter-only updates do not reset
them. Updating all outputs is sequential; invalid filters are validated first,
but concurrent shutdown or I/O errors can still leave a partial update.
Cross-output atomic publication is not promised. See
[configuration](configuration.md) for the advanced per-Runtime configuration
transaction.

Environment variables are adopted explicitly by the application:
`kron.environment.merge(.{ .environment = kron.environment.fromMap(init.environ_map) })`
produces a `filter_spec` that can be assigned to each `route.filter`. Logging
calls do not read the environment or configuration files.

Ordinary multi-producer use should call `scoped` and use shared queues; thread
attachment is not required. SPSC is an advanced option for fixed OS threads and
should be used only after the application has verified a benefit:

```zig
const log = try logging.attachThread("worker");
_ = try log.tryEmit(.info, "ready", .{});
try log.detach();
```

The scope is copied at attach time, and every SPSC output obtains one channel.
If any output's channel budget is exhausted, the whole attachment is rolled
back. The number of attachable threads is constrained by the smallest SPSC
budget. A handle may be used only on its owning OS thread; `detach` invalidates
all copies and derived handles. An old handle never obtains a new attachment.
Channels are preallocated at initialization and remain after detach so the
consumer can drain them.

An ordinary `scoped` logger may be used by multiple producers and still uses the
ordinary shared queue on SPSC pipelines. Tasks that migrate between threads
should use an ordinary logger. Each channel preserves producer order; multiple
channels and independent outputs do not guarantee one global order. Stop
producers and join/detach before shutdown. See
[threaded.zig](../examples/threaded.zig).

## Memory, Mmap, and completion boundaries

Memory is suitable for ordinary background output; records not yet delivered
are lost on abnormal process exit. Mmap requires an explicit path. Accepted
records enter a file-backed mapped queue, and reopening validates and recovers
complete pending records automatically. Every Mmap route must output to a file
or rolling file, including best_effort routes; stdout/writer routes should use
Memory or sync. Advanced custom recovery sinks use Runtime.

See [mmap.zig](../examples/mmap.zig) for a complete mixed example: the Mmap file
and Memory stdout both emit local time, the file is required, and stdout is
best_effort. Reopening with the same journal/layout/target/time identity
recovers automatically; after a clean shutdown, only new events are appended.

| Boundary | Memory | Mmap |
| --- | --- | --- |
| accepted | Copied and committed to an in-process queue | Copied and committed to the mapped queue; not a power-loss guarantee |
| written | Prior records drained and the sink write barrier completed | Additionally advances applicable reclamation/checkpoints |
| durable | Synchronizes supported output files; the queue remains non-persistent | Synchronizes applicable files and the journal/checkpoint |

The default is `reclaim_after = .written`; durable reclamation requires Mmap and
adds synchronization cost. Global `flushDurable` skips best_effort outputs; if
another required output does not support durability, it returns
`UnsupportedDurability`. A best_effort output explicitly selected by
`flushOutputsDurable` must also satisfy the requirement.

Mmap recovery allows at-least-once duplication, for example when a crash occurs
after the file was written but before the queue acknowledged it. Each pipeline
has its own session/channel/sequence and configuration generation, which can be
used for per-output deduplication; add an application `event_id` to correlate
the same logical event. The `timestamp_ns` and source of one event are
consistent, but output identities are not guaranteed to match.

SPSC file names include the ordinary journal and channel files such as
`app.journal.thread-0.journal`, all counted against the budget. Diagnostic tool:
`zig-out/bin/kroncat --json --recover app.journal`; read-only export does not
replace Runtime target-identity validation. See
[configuration](configuration.md) for cross-generation recovery and leases.

## Prepared events and std.log

Asynchronous prepared events require `schema_capacity > 0` on each asynchronous
route, and schemas count against the queue budget. Synchronous routes use
ordinary capture. Registration is a cold path; `Logging` owns the bindings until
destroy.

```zig
const shape: kron.Event = .{
    .level = .info,
    .scope = "worker",
    .message = "request {d} completed",
    .message_template = true,
    .timestamp_ns = 0,
    .format_args = &.{kron.kv("0", @as(u64, 0))},
    .fields = &.{kron.kv("status", @as(u16, 200))},
};
const log = try logging.prepared(shape);
_ = try log.tryLogf(.info, "request {d} completed", .{@as(u64, 42)}, .{ .status = @as(u16, 201) });
```

The attached variant uses `attachPreparedThread` and `detach`. A shape binds the
message template, field order, and kinds; changing them returns
`SchemaMismatch`. Use the advanced metadata interface for optional full-kind
selection; see [schema](schema.md) and [prepared.zig](../examples/prepared.zig).
Prepared-event benefits are workload-specific and not guaranteed to be faster
for every event.

Configure the standard logging bridge in the application root module:

```zig
const LogBridge = kron.Logging.std_log;
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = LogBridge.logFn,
};
```

Call `bindStdLog` after initialization, and `unbindStdLog` after all `std.log`
users have stopped. `Logging.destroy` removes only its own binding. The bridge
uses a bounded 16 KiB producer formatting buffer; inspect
`LogBridge.statistics()` for unbound/oversize/errors. See
[std_log.zig](../examples/std_log.zig) for a complete example.

## Global owner (optional)

When library code cannot pass a logger through every layer, the application may
install a process-wide `Logging` owner. The scope is chosen at the call site, so
different libraries can use their own stable names:

```zig
kron.setGlobalLogging(logging);
defer kron.clearGlobalLogging();

kron.info("mylib", "connected", .{ .host = host });
kron.infoAt(@src(), "mylib.http", "request done", .{ .status = @as(u16, 200) });
kron.logfAt(@src(), .info, "mylib.db", "pool size {d}", .{@as(u8, 10)}, .{});
```

`global.scoped(scope)` returns `?Logger`, or null when no owner is installed;
`enabled(level, scope)` can check before constructing expensive fields. The
global slot stores exactly one `*Logging`; install it before starting workers
and clear it after all users stop. Tests and multi-instance scenarios should
inject `Logging.Logger` explicitly. All global calls are no-ops when no owner is
installed. Entries with `At`, such as `logAt`/`logfAt`/`infoAt`, accept
`@src()` explicitly to preserve structured source information.

## Time, trace, and source location

`route.timestamp` accepts `.{}` (readable UTC), a fixed offset/precision, or
`.{ .zone = .local }`. Local time follows OS timezone/DST rules and is cached per
whole event second; asynchronous routes convert in the consumer, while
sync/fallback_sync routes convert on the calling thread. On Linux, enable
`.@"system-local-time" = true` or link libc in the application, and keep `TZ`
stable at runtime. See [time handling](time.md).

```zig
const traced = log.withTrace(.{
    .trace_id = .{1} ** 16,
    .span_id = .{2} ** 8,
    .flags = 1,
});
_ = try traced.tryLogfAt(@src(), .info, "response {d}", .{@as(u16, 200)}, .{});
```

The example IDs are illustrative; applications pass valid correlation IDs.
Trace context propagates explicitly and is not generated automatically or
inherited by asynchronous tasks. Ordinary logging methods do not record source;
`At` methods accept the call-site `@src()`.

JSON source retains module/file/function/line/column, while `scope` is the
application's business-component label. Text prints
`source= examples/mmap.zig:line:column` using a repository-relative path without
outer quotes, which makes IDE terminal links work. `@src().file` is relative to
the module source root; this repository imports from the root `examples.zig`, so
the `examples/` prefix is preserved. Applications whose entry point is
`src/main.zig` can use the compile-time mapping:

```zig
_ = try log.tryLogfAt(kron.source.fromModule("src", @src()), .info, "request {d} completed", .{request}, .{});
```

The helper preserves other source fields, normalizes `/`, and rejects absolute
paths and `..` that escapes the repository root. Logging calls do not inspect
files or join paths. Pass the repository-relative source directory for each
module separately.

Text prioritizes readability and uses `key= value`; logfmt keeps parseable
`key=value` with quoting/escaping as needed; JSON preserves structure and types;
binary is for tooling. Do not parse text with a logfmt parser. See
[source_location.zig](../examples/source_location.zig) for complete source
output.

## Rotation, deadlines, and verification

Configure rotating files directly in `route.target.rolling_file`. Three choices
are supported:

| Configuration | Trigger |
| --- | --- |
| `max_bytes = 10 * 1024 * 1024` | Rotate when the next complete record would make the active file exceed 10 MiB |
| `rotation_interval_ns = 60 * std.time.ns_per_s` | Rotate before the next non-empty record after 60 seconds from the first record in the current round |
| Both set | Rotate when either condition is met; one record triggers at most one rotation |

```zig
.{
    .name = "hourly",
    .target = .{ .rolling_file = .{
        .path = "app-hourly.jsonl",
        .rotation_interval_ns = 60 * 60 * std.time.ns_per_s,
        .retention = 24,
        .backend = .portable,
    } },
    .mode = .asynchronous,
    .format = .json,
}
```

`max_bytes` defaults to null, disabling the size condition;
`rotation_interval_ns` defaults to null, disabling the time condition. At least
one must be set. Time rotation uses a monotonic interval, resets on
create/reopen, does not accumulate process downtime, and does not align to the
hour or midnight; no empty archive is created when no new logs arrive. A single
record must still fit `buffer_bytes` and, when the size limit is enabled,
`max_bytes`.

Archives retain the active file and `.1` through `.retention`, with `.1` being
the newest. Target and journal paths must be distinct; duplicate targets or
journal conflicts make creation fail. The complete
[rolling.zig](../examples/rolling.zig) demonstrates independent size-based and
time-based files plus a stderr output.

Deadline-aware control uses `kron.Deadline.after(io, std.time.ns_per_s)`. All
pipelines share the absolute deadline, and resources remain valid after a
timeout. `shutdown` has already closed all admission, so retry `shutdown` to
confirm and destroy after users stop. Single-threaded builds support only sync,
ordinary flush, and shutdown; deadline variants return
`TimedControlUnavailable`.

The default path remains allocation-free per event, but multiple outputs add
their own copy, encoding, configuration, and background-thread costs. Hot paths
with one target can use `scopedOutput`; an already-encoded record cannot be
reused across independent queues. Same-format reuse is still possible across
multiple routes in an advanced Runtime shared pipeline, where the application
manages sink lifetime.

## Performance mode selection

| Scenario | Recommended mode | Current evidence |
| --- | --- | --- |
| Recovery, CRC, three checkpoints, multiple routes, rolling, or durable required | Default `Logging`/`Runtime` | Durable default path; the complete contract remains enabled |
| High-throughput async JSON while retaining journal/CRC/recovery | `render_cache` opt-in (adaptive backlog) | Volatile cache only; journal/CRC/recovery remain, and recovery falls back to deferred rendering |
| Highest P1 memory or P4 throughput, no recovery required | `text_format = true` opt-in | Opt-in fast path; default durable/CRC/recovery/queue contracts are unchanged |
| Highest P1 mmap throughput, single producer, no recovery | `MmapSpool` opt-in | Non-durable fast mode; not a replacement for the durable path |
| P1 mmap with journal/recovery required | Default durable `Runtime` | Not the fastest mode; production defaults remain conservative |

Selection rule: first choose the default path from recovery/durable
requirements. Use adaptive `render_cache` when async JSON must retain
journal/CRC/recovery. Use `text_format` or `MmapSpool` only when the application
explicitly accepts that a crash may lose tail records. `text_format` targets the
highest P1 memory/P4 throughput, while `MmapSpool` targets the highest
single-producer P1 mmap throughput. Durable P1 mmap with the cache remains behind
the previous tracing comparison; prefer `text_format` or `MmapSpool` only when
non-durable operation is acceptable.

Cross-library reference harnesses and their measured evidence are no longer
tracked in this repository. The recommendations above describe the local
contract and retained opt-in paths, not a current cross-library ranking.

## Mmap spool fast mode

`kron.MmapSpool` is a non-durable opt-in fast mode with one producer per spool:
the producer renders final JSON directly into a file-backed mapping, one writer
thread schedules `msync(MS_ASYNC)` at roughly 1 MiB intervals, and `shutdown`
truncates the file to the rendered byte count. There is no journal, CRC,
recovery, ring, or consumer. The default `Logging`/`Runtime` durable path is
unchanged.

```zig
const spool = try kron.MmapSpool.create(allocator, io, .{
    .path = "app-fast.jsonl",
    .capacity_bytes = 64 * 1024 * 1024,
    .timestamp_period = 64, // optional: reuse one capture for 64 clock calls
});
defer spool.destroy();
const log = spool.logger("app");
_ = try log.tryEmit(.info, "event", .{ .field0 = @as(u64, 1) });
try spool.flush(.written);
try spool.shutdown();
```

Multi-threaded applications use one spool per thread: each thread creates its
own path and channel, avoiding a shared tail/queue. The file count equals the
producer count, and the application is responsible for merging or archiving
them separately.

```zig
const spool = try kron.MmapSpool.create(allocator, io, .{
    .path = try std.fmt.allocPrint(allocator, "app-fast.thread-{d}.jsonl", .{thread_id}),
    .capacity_bytes = 64 * 1024 * 1024,
    .channel = thread_id + 1,
    .timestamp_period = 64,
});
defer spool.destroy();
const log = spool.logger("app");
// This thread owns the spool; finish with flush(.written) + shutdown().
```

Boundaries:

- Each spool supports exactly one producer. `channel` is configurable (use a
  different value per thread in multi-threaded use), and `sequence` starts at 1
  and increments within each spool.
- `flush(.written)` only makes dirty pages visible to readers; it is not device
  durability. `flush(.durable)` returns `UnsupportedDurability`. A process crash
  may leave a partial tail record; `shutdown` truncates to the last complete
  record.
- `capacity_bytes` is the mapping/memory budget. Exhaustion returns
  `dropped_full`; a record larger than the remaining space returns
  `dropped_oversize`. Partial records are never published.
- `timestamp_period > 1` reuses one clock capture; staleness is bounded by
  clock-call count rather than time. Keep it at 1 when precise timestamps are
  required.
- Use the default `Logging`/`Runtime` when recovery, CRC, three checkpoints,
  rolling/multiple routes, or durability are required.

Performance evidence and cross-library comparison reports are not tracked in the
repository. See [examples](../examples/README.md) for runnable examples and the
verification commands below.

```sh
zig build test-logging test-outputs test-route-policies -Doptimize=ReleaseSafe -j1
zig build run-file-stdout-local-time run-mmap run-route-policies -Doptimize=ReleaseSafe -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
zig build test-package-distribution check-platforms -Doptimize=ReleaseSafe -j1
```

API migration: replace `.output` with
`.outputs = &.{.{ .target = ... }}`; move top-level mode/queue/filter and similar
settings onto the corresponding route; replace `.output.multiple` with an
`outputs` list; configure redaction on each affected route before capture, or use
`Secret` to prevent capturing the original value; pass the output name when
borrowing a Runtime.
