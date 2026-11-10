# Application entry, event capture, and output architecture

Applications integrate through `kron.Logging.create`, which provides a unified
`outputs` list. One Logging instance manages all files, rotation, standard-stream
writers, and Runtime lifetimes. Each route is an independent pipeline with its
own mode, queue, overflow, filtering, sampling, redaction, format, and
acknowledgement boundary. The default is one stderr/sync/text/info output; add a
target by adding a list element.

## Mapping to tracing

The design borrows Rust tracing's responsibility separation, static metadata,
and composition style while keeping event capture independent of output
resources:

| tracing design | kron equivalent |
| --- | --- |
| Instrumentation separated from subscriber | Logger captures a typed Event; Logging manages output pipelines |
| Static metadata and callsite interest | Zig comptime field/format validation, static minimum level, versioned filter caches |
| Values separated from static definitions | Ordinary inline capture; explicit prepared registration of scope/template/shape |
| Layer composition for filtering and output | Each route in the `outputs` list configures policy, queue, and target independently |
| Span context | `withTrace` plus borrowed/owned context; the application propagates explicitly |
| Application configures one subscriber | One Logging owner and one scoped/emit/flush/shutdown API |

These mappings do not imply that kron implements tracing's full span registry,
task instrumentation, or ecosystem layers. Official references:
[tracing](https://docs.rs/tracing/latest/tracing/),
[Layer](https://docs.rs/tracing-subscriber/latest/tracing_subscriber/layer/trait.Layer.html),
[Filter](https://docs.rs/tracing-subscriber/latest/tracing_subscriber/layer/trait.Filter.html).

## Capture and independent pipelines

The composite logger first performs level/filter/sampling admission separately
for each output. If no output admits the event, typed fields, lazy providers, and
the clock are skipped. After outputs are selected, field descriptions and the
timestamp are constructed once, and the same Event is submitted to each Runtime;
before copying into its own Memory/Mmap queue, each Runtime applies effective
redaction and predicates and retains its own configuration generation, session,
and sequence.

Asynchronous consumers perform text/JSON/logfmt formatting, including local time
cached per event second. Sync and fallback_sync deliver on the calling thread.
Dynamic bytes are deep-copied before asynchronous acceptance, so the background
never borrows the producer stack or an arbitrary formatter.

Each Runtime independently owns its sampling quota, queue, worker, scratch,
configuration cache, target identity, and recovery data. Route fields carry
defaults, and sampling/redaction are configured per route. Use `Secret` when the
original value must not enter any output, or ensure that every relevant route's
effective rules cover the field.

Independent queues add memory, thread, copy, and encoding cost. One call still
submits to outputs sequentially, and a block or slow synchronous sink extends
producer waiting; best_effort does not automatically change backpressure. A
low-priority output can explicitly use asynchronous `drop_newest`.

## Hot path and ownership

`scoped` returns a generic Frontend owned by its owner, avoiding a generic
dynamic layer chain and per-event allocation. A single output uses a small
admission frame and calls that Runtime's admission/submit; multiple outputs use
preallocated batch admission storage, retain up to 64 admissions, and release
them in reverse order, preserving the Runtime admission stack and generation
protection. Internal methods borrow the current call's owner, while public
logging methods still fix their scope/context/trace state by value. At most eight
independent Logging instances may nest; recursion within the same Logging is
rejected; the lower-level Runtime simultaneous admission limit remains 64.

`scopedOutput(name, scope)` returns the original logger for the named Runtime and
can be used for single-target hot paths. `attachThread` obtains each SPSC
pipeline's channel from preallocated attachment slots at creation, copies the
scope, and uses generation/thread checks to prevent cross-thread use and old
handle revival. Prepared bindings are allocated on the cold path and owned by
Logging until destroy.

Multiple outputs encode separately; an encoded record cannot be reused across
different queues. Within one advanced Runtime pipeline, multiple routes may
still share encoding when format/time match, but their mode/queue and capture
protection are shared. This entry is for applications that explicitly need those
trade-offs and does not add a second owner to ordinary integration.

## Results and completion boundaries

One call is not a cross-output transaction: a required-output failure still
attempts other admitted outputs, and partial success does not roll back;
best_effort failures are recorded in per-output results and diagnostics.
`lastResults` returns borrowed results from the current OS thread's most recent
dispatch in `outputs` order; later asynchronous I/O failures are reported through
health and flush/shutdown.

Health aggregates per output submission, so one event written to two places
counts twice. Global durable confirms only required outputs; by-name durable
confirms every explicitly selected output. All control operations pre-check
callback reentrancy, shutdown closes all admission before draining sequentially,
and deadlines share one absolute time. A timeout does not release resources still
in use.

Each Mmap pipeline independently validates journal path, layout, stable file
identity, and record versions. Restart still uses at-least-once recovery and does
not promise identical delivery order or consistent commits across outputs. Use an
application `event_id` to correlate a common event and session/channel/sequence
for per-output deduplication.

## Ordinary entry and advanced extensions

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{ .name = "file", .target = .{ .file = .{ .path = "app.jsonl" } }, .mode = .asynchronous, .format = .json },
        .{ .name = "stderr", .target = .stderr, .filter = "warn" },
    },
});
defer logging.destroy();
logging.scoped("http").info("completed", .{ .status = @as(u16, 200) });
try logging.shutdown();
```

Borrow a Runtime with `try logging.runtime(name)` for cross-generation
configuration, external sinks, explicit schema metadata, and clock selection. Do
not destroy that Runtime separately. Cross-output filter updates are sequential;
use the Runtime generation interface when a single-engine atomic configuration
transaction is required.

See the [usage guide](usage.md) for detailed parameters, lifetime, and complete
examples. Performance must be measured end to end; independent pipeline
capabilities do not automatically provide a general advantage over other logging
libraries.
