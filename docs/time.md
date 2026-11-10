# Log time handling

Time support is scoped to actual logging use: UTC and explicit fixed-minute
offsets, optional system local time, Gregorian date conversion, RFC3339/ISO8601
parsing and output, exact durations, and same-second caching. The default fixed
offset path remains pure Zig; explicit local mode uses the operating system's
timezone rules, including DST, and does not bundle an IANA database or implement
its own DST algorithm.

Existing Clock, StandardClock, NativeClock, and qualified TSC handle time
acquisition; this layer handles representation, conversion, and output. Events
keep the existing `i64` Unix-nanosecond `timestamp_ns`, covering roughly
1677-09-21 through 2262-04-11. Absolute wall time can move backward, and log
output preserves the acquired real value; deadlines, sampling, and rotation
continue to advance on an independent monotonic clock.

## References and trade-offs

| Source | Confirmed design | Adopted here |
| --- | --- | --- |
| Abseil Time/CCTZ | Absolute time, civil calendar, and duration are distinct; timezone conversion is explicit | Timestamp, Date/DateTime, Duration, and UtcOffset are separate representations |
| Howard Hinnant date | Converts dates by Gregorian cycles and handles negative epochs/year boundaries | Integer calendar conversion over a 400-year cycle, verified by full-cycle round trips and a Python oracle |
| Go time | Wall time and monotonic time serve different purposes; serialization does not carry in-process monotonic values | Event wall time and deadline clocks remain separate; monotonic readings are never turned into dates |
| Jiff/Temporal | Date arithmetic differs from elapsed duration; ambiguity/boundaries are rejected or handled explicitly | Month arithmetic explicitly chooses reject/clamp, out-of-range values do not wrap; local conversion follows platform rules |
| spdlog / Foundation DefaultFormatter | Cache dates per second and write numbers directly | Each route owns its date cache; same-second local time converts once, and cross-second/backward jumps recompute |
| Quill | Consumer renders event time and caches readable dates | Memory/Mmap async local conversion runs in the consumer; the producer captures only Unix nanoseconds |
| RFC3339 | Explicit offset, limited precision, unknown offset, and leap seconds have different semantics | Requires `Z`/`±HH:MM`; rejects `-00:00` unknown offset; does not silently truncate beyond 9 digits |

Fixed-offset measurements are historical local observations. POSIX local
conversion depends on libc (explicitly enabled); Windows uses native APIs. No
upstream implementation was copied, and the surveyed sources do not imply that
every general time capability is implemented here.

## Representation and safety boundaries

- `Date` covers years 1..9999 and rejects year 0, invalid months/days, and
  invalid leap days. Calendar month addition at month-end must choose reject or
  clamp; day/month addition outside range returns an error.
- `Timestamp` keeps the event's original `i64` Unix nanoseconds; construction and
  duration addition return `OutOfRange`/`Overflow`. `Duration` is `i128`
  nanoseconds and can represent the difference between extreme event timestamps;
  months are not implicitly converted to a fixed number of seconds.
- `UtcOffset` consists of fixed minutes; RFC3339 allows ±23:59. Offsets do not
  include DST; for example, `+08:00` is passed explicitly by the application as
  480 minutes and does not change with seasons.
- Nanosecond precision defaults to the full 9 digits; seconds/milliseconds/
  microseconds explicitly truncate fractional digits downward, and auto removes
  only trailing zeros without losing existing precision. Negative epochs use
  floor seconds and a non-negative fractional part, so -1 ns is
  `1969-12-31T23:59:59.999999999Z`.
- Parsing accepts RFC3339 `T`/`t` and `Z`/`z`, and rejects missing offsets,
  invalid dates, trailing garbage, precision beyond nanoseconds, and leap
  seconds. POSIX timestamps cannot distinguish leap seconds, so `second=60`
  returns `LeapSecondUnsupported` rather than converting to the next minute.
- A Formatter is owned by the caller or route and accessed serially; kron does
  not use a shared date cache. Fixed mode never reads the system timezone; local
  mode skips the platform conversion within the same second and converts on
  cross-second/backward jumps. No bytes are written before the output buffer is
  known to be sufficient.

Fixed mode uses an explicit offset and does not read files, the system timezone,
or the network after initialization. Local mode explicitly reads the platform
timezone; rule availability and environment lifetime follow the contract below.

## Logging integration

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
            .timestamp = .{
                .offset = try kron.time.UtcOffset.parse("+08:00"),
                .precision = .nanoseconds,
            },
        },
    },
});
defer logging.destroy();
```

JSON/logfmt keep the original `timestamp_ns` and add a readable timestamp; text
replaces the numeric prefix with an RFC3339 date. Binary keeps the original Unix
nanosecond event, and a readable timestamp configuration returns
`InvalidTimestampFormat` during creation/replacement. The default
`timestamp=null` preserves the original output and recovery fingerprint and adds
no date-conversion cost.

Each time-enabled route generation owns one Formatter, counted against the
configuration memory budget, allocated during initialization or configuration
replacement, and updated under the original delivery lock during delivery. New
events and old pending events use the offset/precision of their own generation;
filter-only reload does not reset this route state. Offset and precision are part
of output identity and enter the optional recovery fingerprint extension;
changing them on recovery returns `RecoveryRouteMismatch`. Cache contents do not
enter the fingerprint.

Within an advanced Runtime shared pipeline, targets with the same format and
consecutive identical time configuration reuse this record's encoding result;
independent `Logging` outputs encode separately. Different offsets or precisions
re-encode so one route's time string is never used for another. Cache hits,
backward jumps, cross-day transitions, and configuration changes continue to use
the same safe entry point. Ownership and destruction follow the original
configuration View/record-pin lifetime, and old configuration is not released
early on failure.

Standalone formatting can use `kron.time.rfc3339.format/parse`; repeated
formatting can use a caller-owned `kron.time.Formatter`; the complete encoder also
provides `encodeWithTime`. See
[readable_time.zig](../examples/readable_time.zig).
`zig build test-time -Doptimize=ReleaseSafe -j1` runs five modes, hot
configuration, recovery, and an independent Python calendar oracle;
`zig build bench-time -Doptimize=ReleaseFast -j1` measures same-second caching
and cache misses, with complete output included in the checksum. It is not a log
throughput ranking.

## System local time

Explicitly configuring `.timestamp = .{ .zone = .local }` uses system local time;
`offset` remains UTC by default and cannot be specified together with local.
`timestamp=null` still outputs only the raw number, `.timestamp=.{}` still uses
readable UTC, and existing explicit fixed-offset configurations continue to work.

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{
            .mode = .asynchronous,
            .format = .json,
            .timestamp = .{
                .zone = .local,
            },
        },
    },
});
defer logging.destroy();
logging.scoped("app").info("local timestamp", .{});
try logging.shutdown();
```

`zig build run-local-time -Doptimize=ReleaseSafe` runs the complete program.
Linux consumer applications enable libc linking through
`b.dependency("kron", .{ .target = target, .optimize = optimize, .@"system-local-time" = true })`,
or explicitly set `.link_libc = true` in the application module. Direct
compilation adds `-lc`. The default Linux package does not add a libc dependency
for fixed mode; local initialization returns `LocalTimeUnavailable` when libc is
not linked. Apple/Android use the system libc, and Windows converts through
native APIs.

See [file_stdout_local_time.zig](../examples/file_stdout_local_time.zig) for a
complete file-and-stdout example:

```sh
zig build run-file-stdout-local-time -Doptimize=ReleaseSafe
```

One Logging owner asynchronously writes three records:
`kron-file-stdout-local-time.jsonl` appends JSON Lines, stdout emits readable
text, and both configure the same `.timestamp = .{ .zone = .local }`. Both
targets use required delivery, and shutdown confirms written; that confirmation
is not durability. The example build links the system library needed for local
time automatically.

Each route has its own Formatter. The cache key includes the event's whole Unix
second and mode; within the same second it retains year/month/day/hour/minute/
second and offset, updating only the fractional part per event, and refreshes on
cross-second, backward jump, or mode/fixed-offset change. Local system
conversion provides the date directly, without a second Gregorian conversion.
The event timestamp is used rather than the consumption-time current time, so
backlog and recovered records preserve their original instant.

Asynchronous Memory/Mmap shared/SPSC and inline/schema delivery all convert on
the consumer side. Synchronous mode and explicit `fallback_sync` deliver on the
calling thread and therefore format there as well; the local cache does not
change this contract. Within one advanced Runtime pipeline, two routes with the
same format and time identity may reuse this record's encoding result; `Logging`
independent pipelines maintain separate caches and encodings.

POSIX uses `localtime_r` with the process-start `TZ` or the system default
timezone; Windows uses the dynamic timezone conversion API. kron does not call
`tzset`, modify the process environment, or monitor live system timezone
changes. Keep `TZ` and the system timezone configuration stable at runtime;
restart the process when the timezone changes. Platform libc caching of system
updates is platform-defined, and recreating a Formatter alone cannot promise a
libc rule reload. DST uses platform rules for the event timestamp rather than
freezing one startup offset for the whole year.

Timezone-source identity is captured at initialization/configuration
publication: POSIX `TZ` rules or the selected timezone file contents, Android
timezone properties and tzdata, and Windows dynamic timezone information. This
identity enters the route recovery fingerprint; changing the timezone source on
Mmap reopen returns `RecoveryRouteMismatch` instead of silently replaying into a
new representation. kron does not copy the complete OS timezone database, so
this source check does not provide a complete snapshot guarantee against
runtime external modifications or Windows historical registry rule changes.

Timezone-source reads are bounded (at most 4 MiB per file, with bounded
environment names/paths) and run only during initialization and configuration
publication. System conversion failures return explicit errors. Historical
timezones with second-level offsets cannot be represented as RFC3339 minute
offsets and return `NonMinuteLocalOffset` rather than rounding or pretending to
be UTC. The logging encoder preserves its existing encoding-error propagation
boundary.

A standalone Formatter can use `Formatter.initWithIo(io, .{ .zone = .local })`
with serial caller access; `Formatter.init(.{ .zone = .local })` is available
for standalone formatting, while Runtime uniformly uses initialization with
source identity.

Verification commands:

```sh
zig test src/time/root.zig -lc -O ReleaseSafe
zig build test-local-time -Doptimize=ReleaseSafe -j1
```

Unit tests verify that 4096 same-second timestamps trigger exactly one platform
conversion, along with cross-second, backward-jump, mode-change, and short-output
buffer cases. Public pipeline tests cover Memory/Mmap × shared/SPSC ×
inline/schema (eight groups, 96 records each); reservation gaps prevent producer
conversion during delivery, draining converts once on the consumer thread, and
the allocator is not called after Runtime initialization. A Python zoneinfo
oracle independently verifies 372 outputs across six timezones × five modes in
isolated `TZ` processes, including DST, half-hour/forty-five-minute offsets,
backward jumps, future dates, recovery rejection after timezone changes, and
historical non-minute offsets.

A standalone ReleaseFast formatting measurement used 70 samples of 100,000
records each; cached and stateless checksums/byte counts matched for 7 million
complete strings. Same-second local median was 132.167 → 24.372 ns/record,
cross-second 131.438 → 129.840 ns/record, and backward-jump loop 132.316 →
24.548 ns/record; same-second platform conversions fell from 100,000 to one.
The measurement includes string hashing, did not pin CPU or isolate the host,
and does not represent complete logger throughput or a cross-library ranking.

The fixed-offset historical cache measurement is retained below; its numbers are
not current local-time performance or a new cross-library ranking.

## Verification and cache measurement

Calendar tests cover the complete Gregorian 400-year cycle of 146,097 days; nine
substantive time tests include negative epochs/extremes, 400-year boundaries,
explicit month clamping, RFC parse failures, and 4,096 random timestamp/fixed-
offset round trips plus parse mutations. An independent Python `datetime` oracle
verifies another 4,166 nanosecond timestamps/offsets and 5,845 dates, with exact
weekday and day-of-year agreement and no floating-point second conversion.

Five external integration tests cover text/JSON/logfmt, sync/shared/SPSC
Memory/Mmap across five modes, no Runtime allocation after initialization,
configuration replacement with backlogged old events, full initialization-OOM
scanning, multiple targets with the same format but different offsets, and
recovery after a real journal shutdown. Changing offset or precision is rejected;
correct original-configuration recovery restores `timestamp_ns=0` and produces
`+08:00` output. Invalid offsets or binary readable time fail before writing.

Forty standalone formatter samples consumed 4 million complete format strings;
cached and stateless checksums and byte counts matched. Local medians from five
runs per group, including timestamp update and complete output hash, were:

| Input | No cache ns/call | Cache ns/call | Date conversions per 100,000 calls |
| --- | ---: | ---: | ---: |
| Same Unix second | 52.33 | 21.53 | 1 |
| Next second every call | 50.81 | 51.63 | 100000 |
| Fixed offset switch every call | 52.27 | 53.23 | 100000 |
| Cross-second backward loop | 52.15 | 22.86 | 150 |

A cache miss costs close to no cache, while a hit avoids repeated calendar
conversion; seconds and offsets jointly determine the cache, so monotonic
wall-clock progress cannot be assumed for hits. These standalone numbers are not
production latency, complete-file throughput, or cross-platform gains.

Earlier fixed-offset time module Debug/ReleaseSafe runs passed 10/10 each (one
import fixture and nine substantive tests); the full ReleaseFast library passed
81/81 build steps and 498/498 Zig tests. Nine-target ReleaseSafe builds compiled
the public time/logging paths, and time integration, file faults, configuration
23/23, and the independent Python oracle passed. The readable-time example
actually wrote a JSON file asynchronously on Linux and independently verified the
raw nanosecond values. Windows/macOS/Android/iOS device execution still needs
qualification; compilation is not a substitute for execution.
