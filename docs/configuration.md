# Route and policy hot replacement

Ordinary applications configure independent pipelines through
`Logging.outputs`; mode/queue/overflow/redaction/sampling and similar settings
are set per route, and omitted fields use the `Route` type defaults. Each route
applies redaction before writing to its queue and owns its sampling quota. See
the [usage guide](usage.md) for the unified API.

The rest of this document describes multiple routes within one advanced Runtime
pipeline and immutable configuration transactions. They share queue/capture
protection, which differs from `Logging`'s multiple independent pipelines. Borrow
the corresponding engine with `try logging.runtime(name)`; do not destroy it
separately.

`replaceConfiguration(routes, policy)` publishes an immutable configuration
generation. Policy contains the default scope filter, sampling, and recursive
redaction; each route may specify filter, format/timestamp, predicate,
sampling/sample_bypass, output redaction, encoding limits,
required/best_effort, and written/durable reclamation boundaries.

```zig
const version = try runtime.replaceConfiguration(&.{
    .{ .name = "json", .sink = new_file.sink(), .format = .json },
}, .{
    .default_filter = "info,http=debug",
    .redaction = &.{.{ .key = "password", .action = .mask }},
});
try runtime.flush(.written);
_ = try runtime.collectConfigurations();
```

Preparation and validation finish before publication. Invalid rules,
insufficient budget, and OOM preserve the current generation.
`configuration_slots` defaults to 8 and limits concurrently retained
generations; old slots cannot be overwritten while old events/operations still
reference them, and the call returns `ConfigSlotsExhausted`. The caller may wait
for old events to drain, collect, and retry.

## Route policy and capture protection

`RouteOptions.sampling = null` inherits the Runtime global sampling; explicit
`.none` or another policy uses this route's independent all-producer budget.
Sampling freezes the route_mask before field capture, and returns sampled when
all routes reject; consumers and recovery do not re-sample. Filter-only updates
preserve all sampling phases, while full replacement creates new state; old
accepted records keep their original mask.

`RouteOptions.redaction` is additional output redaction: it applies only while
rendering the current route, recursively handles attributes and deferred
argument groups, and does not modify another route or the raw queue value. The
global `Policy.redaction` still rewrites events before queue acceptance; output
policy cannot restore masked/dropped values or `Secret` originals. Configure
pre-capture `Policy.redaction` when originals must not enter Mmap; in `Logging`,
set effective redaction on each relevant route or use `Secret` to prevent
capturing the original.

`RouteOptions.max_encoded_record_bytes` is the complete encoding limit for this
output and must not exceed Runtime output scratch. A required overflow fails and
retains the unacknowledged record; a best_effort overflow is skipped and recorded
as a diagnostic. Output redaction/encoding limits enter the recovery fingerprint;
changes cannot silently recover into a different representation. Sampling state
does not enter the recovery fingerprint because route_mask already stores the
acceptance decision. Routes without configured policy do not allocate extra
Policy/Redactor objects.

Configuration publication copies rules and owns route policy; they are protected
by reader/pending/lease until old record delivery and collection finish. The
`zig build test-route-policies` entry verifies these boundaries; see the
[usage guide](usage.md#route-configuration-and-defaults) for unified
outputs/route examples.

## Complete source transaction

`configuration_sources` merges filter, redaction, sampling, sample_bypass, and
predicate field by field with priority defaults < file < environment < explicit.
The environment adapter maps only `KRON_LOG`, passed explicitly by the
application; merge borrows inputs and does not parse or allocate. An empty
filter, empty redaction, `.none` sampling, and predicate `.clear` are explicit
overrides; only missing fields inherit.

Each immutable configuration snapshot precomputes route-level masks inherited
from the global filter, including each route's min_level restriction. Ordinary
inheriting routes read only the corresponding level mask at log-call time;
routes with independent scope filters still check scope thresholds individually,
and an independent filter can accept logs while the global filter is off.
Filter-only reload changes global thresholds without modifying these derived
masks; full configuration replacement recomputes from new routes, while old
events keep using the old snapshot. The mask costs 64 bytes per generation and
does not change route numbering, recovery fingerprints, or persistent format.
See [route filtering](route-filter-performance.md).

When the background consumes a batch, it reuses one protected View for the same
nonzero generation/fingerprint until that batch is delivered, the barrier
completes, and records are acknowledged. The cache exists only within the batch;
cross-generation records are handled separately, and unknown fingerprints still
return errors. On failure, the temporary View is released while record pins and
resource leases remain. Historical generation=0 does not skip the complete
ambiguity check. See [batch configuration reuse](batch-configuration.md) for
behavior and actual lookup counts.

```zig
const version = try runtime.replaceConfigurationSources(routes, .{
    .defaults = .{ .filter_spec = "info" },
    .file = application_policy,
    .environment = kron.configuration_sources.fromMap(init.environ_map),
    .explicit = .{ .sampling = .none, .predicate = .clear },
});
```

The merged `default_filter` and routes/predicate/redaction/sampling are
published once into the same immutable snapshot. After successful publication,
inputs may be released or overwritten; failure preserves the current route
generation, filter generation, and caller sink-lease responsibility. Sink paths
are created by the application and passed as routes; JSON never executes an
arbitrary sink factory.

`replaceConfigurationFile(routes, path, sources)` reads at most 16 KiB of JSON on
the calling thread, replaces `sources.file`, and uses the same complete
transaction. For example:

```json
{
  "filter": "off,worker=debug",
  "redaction": [{"key": "password", "action": "mask"}],
  "sampling": {"kind": "every", "every": 2},
  "sample_bypass": "warn",
  "predicate": "status >= 500"
}
```

Sampling supports none, count (field `count`), every (field `every`), and
token_bucket (`capacity`, `refill_interval_ns`, optional `start_ns`). Integers
preserve the full u64 range; negatives, fractions, and overflow are rejected.
`predicate=null` explicitly clears. Limits are 16 JSON levels, 64 redaction
rules, and the existing configuration budget; unknown fields, duplicate JSON
fields, duplicate redaction keys, invalid values, or OOM prevent publication.
`configuration_document.Document.parse` provides the same parsing for
applications that read files themselves; Document owns strings and `override()`
borrows until deinit. Example: `zig build run-configuration-sources`.

## Filter-only updates

`reloadFilter`, `reloadFilterFile`, `setLevel`/`setLevelChecked` retain the
lightweight update path. Filter decisions are bound to their route generation;
when the binding does not match, the snapshot's own baseline is used. Therefore
a reload after a full `default_filter` still takes effect and does not create a
combination of an old filter with new policy.

Filter-only updates do not allocate after initialization, do not consume route
slots, and do not reset samplers. `setLevelChecked` changes only the default
level, preserves scope overrides, and returns lifetime errors; `setLevel`
records errors through diagnostics. A later
`replaceConfiguration(..., default_filter=null)` inherits the current effective
filter. Writers serialize through `configuration_mutex`; SPSC cache hits read
only publication and owner-local data, without adding shared reader/pending RMW.

Admission fixes the actual filter generation and route snapshot. A same-scope
enabled guard nested inside another Runtime preserves the outer admission
decision until submission completes. Accepted-event decisions are stored in
route_mask/config_generation, and the background does not re-filter.

Ordinary calls first read the bound filter decision, then acquire the route
snapshot; a complete transaction publishes the route snapshot first and the
same-generation filter second. This order prevents a call that already holds the
old route from falling back to that route's original baseline and losing a
previously completed reload. SPSC uses the same observation order after
validating thread ownership; admitted calls use the decision stored in thread-
local state. Runtime-internal filters use an opaque handle, exposing only the
read-only `currentFilterGeneration()`; an independent `DynamicFilter` remains
available for standalone use.

## Old events and resource ownership

Every successful admission fixes the same snapshot until field capture,
redaction, and submission finish. An accepted journal record additionally holds
that snapshot, and the background looks up the original target by the record's
`route_generation + route_fingerprint`; the latest filter, format, or sink never
reinterprets old events.

Ordinary shared admission directly holds the configuration View already
validated during `begin` and releases the reader at `end` or error unwinding; it
no longer converts that View into a pending pin and immediately releases the
reader. Accepted journal records still hold a separate pending pin before
commit, so the background may write/reclaim a record while an unfinished
admission reader still protects the old configuration and sink lease. The
registry's existing reader/pending dual protection continues to block collect/
reuse. Filtered/sampled paths release the local View inside `begin`, and capture
or sync failures also release the admission reader; SPSC continues to use the
channel cache, while control/deadline resources keep the original pending-pin
protocol.

When `RouteOptions.release` is omitted, the caller owns the sink. The caller must
not destroy an old sink merely because a new configuration was published; flush
first, then use `configurationReadyToCollect(version)` and
`collectConfigurations()` to confirm that the old generation can be reclaimed.

When `release = .{ .context = owner, .release = callback }` is provided, a
successful publication transfers responsibility for that resource lease. Leases
with the same context+callback are counted across generations, and the callback
runs once after the last dependency disappears. Publication failure or Runtime
initialization failure does not take over caller ownership. The release callback
runs outside route write locks and Runtime delivery/configuration locks; it may
publish other configurations but must not re-enter shutdown/destruction of the
Runtime currently being cleaned up.

Collect confirms that a candidate retired generation has no producer/record/
control-operation references, completes final required writes and applicable
durable barriers, then reclaims by exact generation token. New retired
generations created during the callback are not mistakenly released by this
collection.

If the extra durable finish returns `UnsupportedDurability`, a generation that
has completed required written and has no pending records may still be reclaimed,
and the global historical durable qualification is withdrawn. Actual
`InputOutput` and similar errors retain the generation/lease for retry; pending
references ensure that records whose required reclaim boundary is not yet met do
not enter this reclamation path.

## Deadline and recovery

`flushRoutesUntil` resolves named routes at call time and holds that generation's
lease in the control task. Publishing a new configuration after a timeout does
not redirect the in-flight operation to a new target.

`flush(.written)` covers retained historical required generations. Global
durable also considers retired historical targets: if a required target that did
not support durability ever existed, Runtime conservatively returns
`UnsupportedDurability`. A durable flush for an explicit route does not declare
other historical targets durable.

On restart, configure the correct current `initial_route_generation` and provide
old generations with undelivered records and their target identities in
`recovery_versions`:

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .routes = current_routes,
    .initial_route_generation = 2,
    .recovery_versions = &.{.{ .generation = 1, .routes = old_routes }},
    .submission = .asynchronous,
    .journal = journal_options,
});
```

Initialization validates the bindings of every record to recover, not only the
first. Missing old targets, identity mismatches, or ambiguity return errors and
preserve the journal; records are never silently delivered to a new file.
Historical resources may be recovered by a new instance, but their stable
recovery identity must match.

`test-configurations` verifies old/new target routing, admitted producers
retaining old policy, capacity/OOM/initialization-failure responsibility, shared
leases, callback reentrancy, deadline leases, and cross-generation recovery. The
hot-routes phase of `test-crash` force-kills a real Runtime and exports records
from both generations in a new process. `test-transactions` verifies complete
source publication, filter-only updates and sampling quotas, failure
responsibility, channel reuse, delayed publication interleaving, nested guards,
and real JSON files. Warmed SPSC counting tests in the root module directly
check that global reader/pending and DynamicFilter reader RMW do not grow.

## SPSC configuration cache

Each attached channel holds its own validated-generation cache. A steady-state
cache hit reads only publication and owner-local data; producer/control shared
counters are separate from channel counters. Accepted records retain the
corresponding channel/generation reference and release it only after
acknowledgement; refresh pins the new generation first, then releases the old
cache.

The cache is updated by the owning synchronized thread and released by detach
after confirming no outstanding admission; collection never modifies the cache
administratively because enabled/filtered may be read outside admission. An idle
attachment may retain an old configuration slot until the thread's next call
refreshes the cache or detaches. This is bounded resource behavior and cannot be
eliminated by forcibly overwriting the old cache.

An outer enabled guard nested inside a callback for a different Runtime returns
the TLS cache generation currently used by the outer Runtime, without refreshing
or releasing early. The public release entry also checks real retirement,
cookie, and active admission, and cannot drop the only pin while an event is
executing.

`max_configuration_bytes` controls per-generation metadata budget; Runtime
defaults to 2 MiB, enough to override 64 fixed-budget routes.
`configuration_slots` limits concurrently retained generations. Field predicates
add fixed configuration storage, so the budget cannot be equated with string
length.
