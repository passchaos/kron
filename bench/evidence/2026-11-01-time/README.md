# Fixed-offset log time

The user explicitly excludes daylight saving. The implementation has no IANA
database, geographical zone guessing, implicit Local, OS-zone query or network.
Timestamp uses the event's exact i64 Unix-nanosecond range; Date/DateTime use a
checked Gregorian calendar, Duration uses exact i128 nanoseconds, and UtcOffset
holds validated fixed minutes. Invalid civil inputs are rejected. Month-end
clamping is explicit. Monotonic deadlines/sampling/rotation remain unchanged.

RFC3339 supports required Z/±HH:MM, 0..9 fractional digits, T/t and Z/z, fixed
seconds/milliseconds/microseconds/nanoseconds or lossless trailing-zero trimming.
Parsing rejects >9 fractional digits, unknown -00:00 and POSIX-unrepresentable
leap seconds. Negative epochs use floor seconds and nonnegative fractions.
The caller-owned cache keys its 19-byte date prefix by Unix second AND offset;
rollback, midnight, extreme timestamps and changed offset remain correct.

Typed routes opt into timestamp options. Text uses the readable prefix; JSON
and logfmt add readable timestamp and preserve numeric timestamp_ns. Binary
rejects readable options. Defaults retain old output and recovery fingerprints.
The immutable route version owns an allocated Formatter within its budget;
only the original delivery lock updates the cache. Offset/precision enter a
non-default recovery-hash extension; cache content does not. Old pending events
retain old options and resource ownership through replacement and failures.

9 substantive time tests include the complete 146,097-day Gregorian 400-year
cycle, checked calendar/duration/instant arithmetic, RFC parsing and 4,096 seeded
timestamp/offset/mutation cases. Independent Python datetime validation covers
4,166 precise timestamp offsets and 5,845 civil dates, weekday and ordinal.
5 public integration tests cover formats, all five runtime/storage strategies,
zero runtime allocation after initialization, pending old/new configuration,
allocation-failure cleanup, actual journal reopen with changed-offset/precision
rejection and multi-sink output distinction. No system-clock precision is removed.

bench/time.zig has 40 samples and consumes 4,000,000 complete format strings.
Stateless/cached checksums and bytes match in every case. Cached same-second
formatting has one calendar conversion per 100K outputs, changing-second and
offset-change have 100K, and a rollback loop has 150. Initial non-affinity-pinned
medians include full-output hashing: same-second 52.33→21.53ns; changing-second
50.81→51.63ns; offset-change 52.27→53.23ns; rollback 52.15→22.86ns. This is not an
end-to-end logging benchmark or portable performance guarantee.

research-sources.json identifies official Abseil/CCTZ/date/Go/Jiff/Temporal and
RFC documents. An initially attempted Jiff design path returned 404; its README
and Temporal documentation informed the type/ambiguity separation. No upstream
code or production dependency is introduced. The user's no-DST constraint takes
precedence over the broader capabilities of those references.

Final verification logs and qualification identify tested sources, actual
platform-object scope and full regression. Non-Linux device execution remains
separate from cross-compilation. The preceding decimal-output optimization has
its own archived 483-test evidence and is not mixed into time performance.

Final Debug and ReleaseSafe standalone time-module checks pass 10/10 each,
including one import fixture. Full ReleaseFast verify-local passes 81/81 build
steps and 498/498 Zig tests, with the existing package/native host, old-format
matrix, compile-fail, differential and process-crash gates. The final ReleaseSafe
gate passes 21/21 steps, nine actual public time/runtime target objects, 23/23
time/file/configuration tests and the independent Python calendar oracle.
native-example.jsonl is an actual asynchronous memory-queue FileSink output;
its exact readable value is independently computed from numeric nanoseconds.
