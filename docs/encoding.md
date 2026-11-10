# Event encoding, validation, and binary archives

The current inline format is v4, and the schema-reference format is v5. A v6
native-integer candidate reduced five-u64 payloads by 40 bytes, but complete
file/PMU screening showed negative instruction, cycle, and throughput results in
some groups; all production candidates were withdrawn. A smaller payload does
not imply faster logging. Frozen scalar/wide/nested/deferred and schema bytes
from the real old writer remain as regression fixtures.

Source locations preserve the complete relative path in the event. Text prints
an unquoted `source= src/http/handler.zig:42:7` for terminal navigation; control
characters, invalid UTF-8, and Unicode line separators are still escaped so a
path cannot inject a new log line. JSON `source.file` remains a valid string, and
logfmt quotes the field according to its key/value syntax. Applications whose
module root differs from the repository root use compile-time
`kron.source.fromModule`, or place the entry point at the repository root; see
[source path integration](usage.md#time-trace-and-source-location).

Merging schema key/type shape checks into the size visitor was tested end to end
and preserved all error ordering, passing 4,096 independent old/new
differentials. Independent PMU showed schema SPSC instructions increased by
0.463%, and complete workflows did not qualify for a throughput gain, so the
candidate was rejected. The current schema still performs a complete tree/length
traversal followed by a separate shape check; invalid trees take precedence over
schema/level and length errors, and failures write nothing to the destination.
Removing one loop is not automatically a speedup.

`codec.encodedSize`, `codec.encode`, and `codec.writeTo` all validate the
complete borrowed event. Cycle detection for arrays/groups, the 8-level depth
limit, duplicate group keys, and the 256-node budget shared by
attributes/arguments have one traversal implementation in `fields.ValueValidator`.
Format-argument top-level keys may repeat; groups inside arguments still require
unique keys.

Length computation uses an observer in the same traversal to count each node's
own wire bytes: keys use a 4-byte length plus key bytes, scalars use a tag and
fixed value, strings/bytes use a tag, length, and contents, and arrays/groups use
a tag and child count. Children are visited by the validator and are not counted
again by a separate recursion. Standalone public value size also validates
first.

Length accumulation uses u64, with each usize item first clamped to
`u32_max + 1`. The final wire format can only carry u32 lengths, so any item over
the limit still returns `TooLarge` after complete tree validation; the sum of
valid items remains exact. At most 256 value/key nodes and five event/source
strings keep the bounded accumulation below 2^42, and comptime limits usize to
at most 64 bits. Length overflow does not hide later cycle, duplicate-key, or
schema shape/level errors; oversized logical slices are not read, and invalid
events or insufficient capacity still fail before writing to the destination.
An independent 8,192-case random/boundary arithmetic test matches wide u128
results.

`ValueValidator.valueWith/fieldsWith/argumentsWith` accept a typed visitor whose
callback observes the current value or Field and cannot recurse or modify the
borrowed tree. A custom visitor error ends traversal immediately and may precede
validation errors for unvisited nodes; codec-internal visitors never return
errors, preserving the complete validation-first contract.

## Binary archive

`encoder.binary.encode` uses `codec.writeFramed` in one call:

1. Validate the complete tree and compute payload length once.
2. Stream into a 256-byte hash buffer and compute payload CRC32.
3. Generate and write the fixed archive header.
4. Stream the payload using the same private wire implementation.

The two payload traversals are required because CRC must be known before the
header is written; duplicate validation and length computation are merged. No
unchecked writer or reusable validation token is exported. Event, descriptors,
keys, and strings/bytes must remain stable throughout the call and Writer
callback, which is a precondition of every borrowed encoding interface.

The default Runtime inline submission path now calls `codec.measure` before the
route predicate, obtains wire length from the same complete tree validation, and
passes that length to `codec.encodeSized` after acceptance. `encodeSized` still
rechecks level and destination capacity and only skips the second length
traversal for the same unchanged event; redaction rewrites borrowed storage and
keeps independent validation/measurement; the latest prepared-schema path reuses
value/nested-key bytes counted during this full-tree check, while shape and
references are still checked at their original boundaries. `codec.measure`
intentionally does not check level, preserving the existing order: tree errors
precede the predicate, and level errors appear only at the accepted write
boundary. Public `codec.encode` still validates the complete tree first, and no
reusable unchecked writer or validation token is exported; misuse with a length
from different fields/messages is rejected by the calling contract and debug
asserts.

Consumer decoded delivery reuses the checked decoder's tree validation:
`codec.decode`/`schema_codec.resolve` set an internal `Event.tree_validated` flag
after checking the wire tree, node budget, depth, duplicate keys, and lengths;
internal `encoder.common.encodeDecoded` skips the second `ValueValidator` only for
that proof and otherwise uses the validation path. Public
`encoder.encode/encodeWithTime` ignore the hint and always validate; Runtime
first uses admission's `codec.measure` or redaction/binding validation, then
`submitSafeDestination` overwrites caller hints with trusted context. Binary
routes continue to use the public validation entry. Tests lock in that a forged
hint on an invalid tree is still rejected by the public encoder, Runtime still
returns `DuplicateKey` for duplicate keys, and decoded text/JSON/logfmt bytes
match the public encoder.

A fused wire-to-JSON path covers common shapes: current v4 inline, a single
JSON/text/logfmt route, non-deferred message, and no format arguments. The
checked wire parser parses header/scope/message/trace/source/attributes once;
nested attributes use a caller scratch arena, and the same JSON/text/logfmt
record as the public encoder is written into scratch; top-level key
deduplication and complete value-tag validation finish before writing to the
sink. Other shapes return `error.Fallback` and use decode+encode. Journal
protocol, public encoder, and validation boundaries are unchanged.

Fused scalars pass through `WireInput.valueWith(receiver)` directly to a writer
compiled per comptime tag, skipping intermediate `Value` materialization and
generic second dispatch. `valueWith` uses the same tag, length, node, depth,
nested, duplicate-key, and arena-budget checks as public `value()`; arrays/groups
are fully parsed before callbacks, public `value()` still constructs the original
`Value`, and public value/event APIs continue to fully validate borrowed trees.
`common.writeTaggedValue` is an internal rendering entry and does not expose an
unchecked writer.

JSON fixed metadata timestamp, session, sequence, route_mask, and
config_generation also call `writeTaggedValue` directly with comptime tags and
raw `i64`/`u64`, without constructing a temporary `Value`, a runtime tag switch,
or widening `u64` to `u128`. Output precision, quoting, decimal handling, and the
text/logfmt paths are unchanged.

Tests lock in that filtered invalid levels still return filtered, invalid trees
still fail before the predicate, and sized writes match public `encode` bytes
exactly. Redaction paths keep independent validation of the original/new tree;
the latest prepared path reuses the final tree length only within the same safe
submission. Public codec and Runtime submission entries still fully validate and
do not accept reusable external credentials.

Tests confirm that size, encode, and stream validate each node exactly once, and
that archive also prepares once. Coverage includes all value tags, independent
and combined node budgets, zero output for invalid trees, error precedence after
size overflow, Secret redaction, and matching wire bytes. Runtime, redaction, and
context each keep their own entry validation; this work does not use "validated
earlier" to skip public submission boundaries.

## Pre-registered schema encoding

`schema_codec.encodedReferenceSize` and `encodeReference` now also count value
lengths through the same validating visitor. Top-level field and format-argument
keys are already stored in the schema and therefore not counted in the reference
payload; nested group keys are still written into the payload, and the
validator's current depth decides whether they count. Both entries perform
exactly one complete tree validation and preserve the shared 256-node/8-level
attributes/arguments budget, cycle checks, and nested duplicate-key checks.

Previously, reference encoding validated the complete event, recursively
validated each top-level value again while computing length, and validated a
third time when the public value writer wrote it. Node-local length accounting
now lives in internal `wire_size.zig`, and low-level byte writing lives in
internal `wire_write.zig`, shared by the two payload codecs after complete
validation. Public `codec.writeValue` still validates independently before
writing; no public module exposes a validation-skipping writer or credential.

Reference encoding keeps the original error order: complete tree errors →
schema shape/type and level errors → wire length limit → destination capacity.
Length uses bounded u64 accumulation, each item is clamped to `u32_max + 1`, and
the wire limit is checked after validation and shape/level checks; failure does
not modify the destination. Schema payload v5/84-byte header, old v2 reads,
inline v4, and old v1/v3 reads are preserved. New tests directly compute lengths
for all scalar/container tags and check one-pass counting, nested keys, duplicate
positional keys, 256-node and depth boundaries, length-overflow precedence, and
zero output from the public value writer for invalid input.

## Performance evidence

`zig build bench-encoding -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5`
covers flat5, two-level nesting, and the maximum 256 nodes, measuring size, value
size, encode, and binary archive separately. Complete-output Wyhash consumption
is included in encode/archive, the clock is read once per batch pair, and no heap
allocation occurs during measurement.

Before-source was frozen separately, and original candidates plus the final u128
candidate were retained. Five alternating before/after rounds produced 600 rows;
each row's checksum, output bytes, payload/value/archive length, fields/nodes,
iterations, and budget matched the baseline. Raw measurement directories are no
longer tracked in the repository.

The first candidate checked overflow per node, adding cost to small events, so
the final accumulator checks limits only after complete tree validation. Several
clock experiments showed clear host/CPU scheduling variance, and all comparisons
were marked inconclusive. User-space perf counts including setup and reporting
support an instruction reduction but are not stable producer latency or
end-to-end throughput. The current result is reduced duplicate work, accurate
boundary tests, and a reproducible benchmark, not an industry ranking.

The 2026-11-01 benchmark added `reference_size_only` and `reference_encode`, with
schema registration, complete round-trip checks, and allocation outside the timed
region. Before-source was frozen separately, application and library were built
with ReleaseFast, subprocess affinity was fixed, and five alternating
before/after rounds each had five repetitions. All 450 paired results matched
exactly on complete-output checksum, wire/archive/reference payload length, and
field/node/buffer budgets.

Reference-length medians for flat5, nested8, and max256 fell by about 23%, 38%,
and 44% locally; nested8 reference encoding fell by about 29%. Flat5/max256
reference-encoding medians fell, but cross-round spread exceeded the 10% noise
threshold, so those results remain inconclusive. Reference-encoding timing also
includes fixture updates and complete-output Wyhash and cannot be converted into
overall producer latency or log throughput.

## Decoder and version matrix

`test-decoder-matrix` provides an independent bounded gate and is included in
`test-fuzz`. The matrix distinguishes three version domains and does not treat
identically named versions as the same protocol:

| Payload | Header length | Schema definition | On-disk container |
| --- | --- | --- | --- |
| Historical self-contained v1 | 68 | none | archive frame v1 |
| Historical self-contained v3 | 76 | none | archive frame v1 |
| Current self-contained v4, scalar/nested | 84 | none | archive frame v1 |
| Historical reference v2 | 76 | scalar v1 | journal file v2 |
| Current reference v5, scalar | 84 | scalar v1 | journal file v2 |
| Current reference v5, nested dynamic/format strings | 84 | nested v2 | journal file v2 |

Eight payload groups each run 2,048 deterministic mutations, every byte
truncation, and short-scratch checks with 0–15 Field capacities. Mutations
include single-byte flips, multi-byte random flips, random u32 structural
lengths, and truncation; successful decoding must re-encode exactly, and missing
historical header fields may only recover as zero. String/key/source sentinel
ranges must lie within the input or schema, and nested descriptors must lie
within caller scratch; canaries outside scratch and unused tails must not be
modified, and failed decoding also verifies that the input is unchanged.
Successfully encoded JSON is checked by an independent standard JSON parser;
invalid deferred formats after mutation may only fail through the Writer error
boundary.

Schema definitions also receive complete-body byte mutations: after modification,
the domain-prefixed SHA-256 and entry CRC are recomputed according to protocol,
then strict `decodeEntry` is called, so structural errors cannot be rejected only
by the old checksum. Valid definitions regenerate canonical metadata and verify
the hash, then reference payloads are parsed. The disk matrix uses eight real
files, each exported twice read-only through the public Reader, verifying events
and raw file bytes. Historical payload fixtures are constructed from explicit
header conversion; independent historical goldens and mixed plain/compressed
reads remain covered by the existing codec/query tests.

This gate is repeatable and resource-bounded, used for compatibility and
regression; it is not proof of covering every input and does not replace
long-running coverage-guided fuzz or hardware-fault qualification.

## Prepared Runtime measurement reuse

The non-redacted prepared Runtime path counts dynamic value and nested-key bytes
during the complete tree check before the predicate, and the private context
reuses them only for the same unchanged event. The canonical definition decides
whether to include dynamic message length; shape/level, queue full/fallback, and
capacity errors keep their original order. Internal `reference_encoding.zig`
shares these primitives, while public `encodedReferenceSize` and
`encodeReference` validate the tree first every time; no public measured encoder
or external token exists. Redaction and consumer independent checks are not
removed, and all ready references/CRC/pins/barriers are unchanged.
