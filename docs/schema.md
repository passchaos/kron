# Persistent schema and pre-registered loggers

A normal v1 journal makes every event self-contained. Setting
`Journal.Options.schema_capacity > 0` explicitly enables v2: data slots still
start at offset 4096, and a fixed metadata table is appended at the end of the
file. Field names, format strings, scope, and source are stored once; reference
events copy only dynamic values, trace information, routing decisions, and
sequence numbers.

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .asynchronous,
    .journal = .{
        .path = "app.journal", .capacity = 256, .max_record_bytes = 4096,
        .schema_capacity = 64, .max_schema_bytes = 4096,
    },
    .routes = routes,
});
const binding = try runtime.prewarmSchema(.{
    .level = .info, .scope = "http", .message = "request {d}",
    .message_template = true, .timestamp_ns = 0,
    .format_args = &.{kron.kv("0", @as(u64, 1))},
    .fields = &.{kron.kv("status", @as(u16, 200))},
});
const log = try runtime.loggerWithSchema(binding);
_ = try log.tryLogf(.info, "request {d}", .{@as(u64, 42)}, .{ .status = @as(u16, 201) });
```

The unified application entry can use `logging.prepared(example)`; SPSC uses
`logging.attachPreparedThread(example)`, which attaches and registers the
corresponding channel internally, followed by `detach` when finished. A
preparation failure rolls back the attachment. See the
[usage guide](usage.md#prepared-events-and-stdlog) for configuration and complete
steps.

Advanced Runtime SPSC uses `prewarmThreadSchema(channel, example)` and
`threadLoggerWithSchema(attached, binding)`, preserving the original attachment's
cookie, generation, and thread constraints. See
[prepared.zig](../examples/prepared.zig) for a runnable example.

## Registration and hot path

Prewarm is an explicit cold path: it generates canonical metadata, checks for
duplicates, commits the definition and synchronizes the file, then publishes an
in-process ready flag. A prepared logger uses the stable reference directly and
does not re-register, parse, or synchronize the schema per event.

Ordinary prewarm infers the current captured value kind from the example.
`schema_site.metadata` and `Runtime.prewarmFormat` generate the complete kind
mask from comptime Args/Fields types, with optional including null and Value able
to override known types; `prewarmMetadata` transforms the drop/mask shape of
fixed redaction before registration. Changing field names/order, format string,
or source returns `SchemaMismatch` instead of silently degrading or creating a
new schema.

Schemas do not store example values; redaction takes effect before metadata and
dynamic capture. Dynamic strings are still copied into the journal before the
call returns. Pre-registered and ordinary loggers share filter, sampling,
context overrides, secrets, flush, shutdown, and error semantics.

## File and recovery contract

- The v2 file header and CRC-protected schema extension define the tail region;
  capacity/stride count against the total journal budget of all channels.
- Each definition occupies an independent fixed slot; IDs are never reclaimed or
  reused during the file lifetime. A full table or oversized definition returns
  an explicit error.
- Content hashing uses the first 128 bits of the canonical metadata SHA-256;
  after a hash hit, the complete metadata is still compared. Addresses or partial
  argument hashes are never used as identity.
- A reference contains ID, version, and content hash; data CRC covers the
  reference and payload.
- A definition must successfully sync after commit before `markReady` and before
  reference events may be submitted; on failure, referencing is forbidden,
  evidence is preserved, and retry is allowed.
- Reopen validates the schema table and every reference before modifying data
  cursors. Corruption, missing definitions, and unknown versions are not treated
  as ordinary filtering.
- `kroncat` copies definitions and payloads read-only, validates a stable
  snapshot, and does not depend on the original program binary or process
  addresses.
- Background delivery expands a reference back into an Event and still emits
  ordinary text/JSON and self-contained archive frames.

The saving is in producer-captured bytes and repeated metadata, not automatically
in fixed data-slot stride occupancy. The v1 default configuration remains
compatible; after enabling v2, do not open the file with old v1 layout options.

Journal file version, event codec version, and archive frame version are
independent protocols. Current self-contained event v4 and schema-reference
payload v5 use an 84-byte header that stores the recovery target fingerprint and
route generation; historical self-contained v1 is 68 bytes, and historical
self-contained v3 plus schema-reference v2 are 76 bytes. The current reader keeps
these historical versions and restores missing routing-identity fields as zero;
unknown versions are rejected explicitly. The archive frame container remains
version 1, and its payload is read according to its own codec version. Legacy
records without a stable route fingerprint can be exported read-only, but Runtime
cannot silently replay them to an unknown target.

Schema definitions have their own versions: scalar definition v1 and
array/group-capable definition v2. Current v5 events may use scalar or nested
definitions; the historical v2 reference-payload compatibility matrix uses scalar
definitions. Do not confuse journal file v2, schema definition v2, and event
reference v2.

## Verification scope

Module tests cover deduplication, collision comparison, metadata deep copies,
table capacity, sync/ready failures, reservation gaps, independent reopen,
Reader read-only recovery, and hot-path allocator behavior. Shared/SPSC prepared
Runtime tests verify actual background delivery output.

`zig build test-decoder-matrix -Doptimize=ReleaseSafe -j1` covers eight input
groups: historical/current inline payloads, scalar schema, nested schema, dynamic
message, and deferred template. Each group runs 2,048 mutations, all truncations,
and short-scratch capacities; a valid decode must re-encode exactly, and every
borrowed string/descriptor must lie within the input, schema, or caller scratch.
Schema definition mutations recompute integrity fields and directly check
structural rejection; eight real files are exported twice read-only through the
public Reader. The matrix is also part of `test-fuzz` and is a bounded
regression, not a replacement for long-running fuzz.

The QEMU harness `--schema` option runs the real v2 writer. In the current
Linux/ext4 trial, the whole QEMU process was force-killed after ACK 3, and restart
confirmed all ACKed file records and the durable checkpoint. This remains a
specific child-VM shutdown trial, not a general physical power-loss guarantee.

## Schema consumer fused output

When a ready ordinary schema event window has at least 64 records, exactly one
JSON/text/logfmt target, no deferred message, and no format arguments, the
consumer can read the definition and dynamic values directly into output scratch,
avoiding top-level field-array materialization and a subsequent attribute
traversal. The definition is still resolved by the journal-owning registry, and
type masks, node/depth, nested descriptors, complete payload length, and schema
identity are still validated; any corrupt record is rejected before complete
rendering and never reaches the sink.

Static key uniqueness is guaranteed by the original schema definition; scope/
source and optional static messages borrow validated definitions, and these
borrows are used only during delivery of the current protected record. Dynamic
messages, historical v2 scalar definitions, nested v5, and all three text outputs
have byte-for-byte comparisons. Windows with fewer than 64 records,
template/args, multiple routes, and binary continue to use materialized resolve;
the canonical definition lookup for the same record may be reused inside
fallback. The cold path for route rejection preserves decode-first, then
route-error precedence.

The original service budget, output written/durable barriers, second CRC
reclaim, configuration pins, and at-least-once recovery contract still apply. The
local CPU changes of this path do not establish a cross-library ranking.

## Value-length reuse in prepared submission

A prepared submission with no redaction rules performs one full-tree validation
before the original predicate and counts dynamic value and nested-key bytes. The
private submission context carries that length only within the same unchanged
call; canonical schema resolution, shape/type/level, full/drop/fallback, and
capacity checks still run at their original boundaries. Trace/header/dynamic
message lengths are added after the canonical payload shape is determined.
`reference_encoding.zig` is an internal shared implementation; public
`encodedReferenceSize`/`encodeReference` still validate the complete tree every
time, do not export a measured encoder or saveable validation credential, and do
not trust `Event.tree_validated` or the caller's `Binding.definition`.

Redaction rewrites the tree and keeps independent validation of original/new
events, without reusing the pre-rewrite length. Ready-reference checks, CRC,
record pins, and barriers for reserve/commit/consumer/reclaim are unchanged. Real
Memory/Mmap × shared/SPSC counting confirms that five values are validated five
times inside Runtime submission and another five times by the public codec;
predicate and full/drop/fallback error order, oversized/invalid levels, forged
hints, and redaction paths have actual tests.
