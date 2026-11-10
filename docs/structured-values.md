# Explicit nested fields

Fields still capture built-in scalars by default; containers are provided
explicitly through `array()` and `group()`, avoiding automatic traversal of
arbitrary pointers or object graphs.

```zig
const details = [_]kron.Field{
    kron.kv("status", @as(u16, 200)),
    kron.kv("password", kron.secret("never capture")),
};
const items = [_]kron.Value{
    kron.fields.fromAny(kron.group(&details)),
    kron.fields.fromAny(@as(u64, 42)),
};
log.info("request completed", .{ .results = kron.array(&items) });
```

Container views borrow caller storage; before asynchronous acceptance, the codec
deep-copies all descriptors, keys, strings, and bytes. `withOwned` likewise
deep-copies all nested storage, and normal emit allocates no heap memory.

An event shares a limit of 8 container levels and 256 value nodes, including
attributes, format arguments, and all children. Cycles, duplicate group keys,
excessive depth, and budget overruns return explicit errors before writing/
acceptance; a valid prefix is never output as success. Decode uses a caller arena
with fixed 256 Field slots and does not allocate while reading.

JSON outputs real arrays/objects, text outputs readable containers, and logfmt
places the complete container representation into one quoted value. `{}`/`{any}`
can render containers in the background; numeric and string format specifiers do
not accept containers.

Redaction matches the complete key exactly at any group level. Dots are not
interpreted as paths. Nested format arguments are also processed before entering
the journal; top-level argument slots and order are preserved so a drop does not
shift positions. The input tree is not modified, and failures clear references to
original values in unused scratch.

The current self-contained event payload is v4/84-byte header, and schema
reference is v5; old v1/v3 and reference v2 reads are preserved. Schema definition
scalar v1 and container v2 are independent of event and journal file versions.

## Explicit object adapters

`Adapter` selects named struct members at compile time and owns fixed Field
descriptor storage. At most 64 members can be selected; member existence, type
support, and unique names/output keys are checked at compile time. Unselected
members are never read.

```zig
const User = struct { id: u64, name: []const u8, password: []const u8 };
var user: User = .{ .id = 42, .name = "alice", .password = "private" };
var storage = kron.Adapter(User, &.{ "id", "name" }).init();
const result = try log.tryEmit(.info, "user", .{
    .user = try storage.capture(&user),
});
_ = result;
```

Capture copies scalars and borrows strings/bytes/explicit containers; the returned
Group borrows the adapter itself, and the next capture invalidates the old view.
Keep the adapter at a stable address and retain source storage until synchronous
encoding or asynchronous acceptance. `withOwned` deep-copies this structure.

`object(selected, &value, field_storage)` can use caller `[]Field` directly;
insufficient storage returns `TooManyFields`. `MappedAdapter(T, maps)` and
`objectMapped` use `FieldMap{ .member, .key }` for explicit renaming. Arbitrary
object pointers, implicit recursive structs, and by-value byte arrays are
rejected; nested values are provided through `array/group` and follow the 8-level/
256-node validation. `zig build test-adapter` and negative compilation gates
verify these contracts.
