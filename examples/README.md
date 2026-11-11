# Runnable examples

Applications start with `kron.Logging`. Examples use Zig 0.16's
`std.process.Init`, and the repository build adds the `kron` import. Run them
with `zig build run-NAME -Doptimize=ReleaseSafe`. See the
[usage guide](../docs/usage.md) for complete parameters and lifetime.

| Name | Source | Demonstrates |
| --- | --- | --- |
| quick-start | [quick_start.zig](quick_start.zig) | Default stderr, typed fields, and shutdown |
| file-logging | [file_logging.zig](file_logging.zig) | Shared Memory, JSON file, redaction, and reload |
| async-memory | [async_memory.zig](async_memory.zig) | Shared Memory to stdout |
| structured | [structured.zig](structured.zig) | Borrowed/owned, array/group, secret/bytes, lazy, trace/source, dates |
| threaded | [threaded.zig](threaded.zig) | SPSC across two OS threads, attach/detach, join, and error propagation |
| rolling | [rolling.zig](rolling.zig) | Independent size/time rotating JSON files plus stderr, file durability |
| prepared | [prepared.zig](prepared.zig) | Mmap/SPSC schema, helper that hides channel indices |
| local-time | [local_time.zig](local_time.zig) | Consumer-side system-local dates and same-second caching |
| file-stdout-local-time | [file_stdout_local_time.zig](file_stdout_local_time.zig) | JSON file + stdout text, local time and source location |
| mmap | [mmap.zig](mmap.zig) | Independent Mmap file + Memory stdout, local time, and durability |
| source-location | [source_location.zig](source_location.zig) | Complete JSON module/file/function/line/column |
| route-policies | [route_policies.zig](route_policies.zig) | `outputs` list, independent mode/queue/overflow, sampling/redaction |
| std-log | [std_log.zig](std_log.zig) | Root `std_options`, bind/unbind, and dynamic filtering |

Advanced-interface examples cover custom configuration, clocks, or lower-level
resources:

| Name | Source | Demonstrates |
| --- | --- | --- |
| basic | [basic.zig](basic.zig) | Runtime multiple outputs, Mmap, environment filter |
| configuration-sources | [configuration_sources.zig](configuration_sources.zig) | Complete source transaction and JSON policy |
| hot-configuration | [hot_configuration.zig](hot_configuration.zig) | Replacing outputs and old-resource lifetime |
| readable-time | [readable_time.zig](readable_time.zig) | Route dates and fixed offsets |
| predicates | [predicates.zig](predicates.zig) | Pre-acceptance conditions and regex |
| tsc-clock | [tsc_clock.zig](tsc_clock.zig) | Explicit qualification and native-clock fallback |

File examples write into the current working directory, usually appending;
rotation removes the oldest archive according to retention. When running
repeatedly, match counts against the latest session. `verify-local` compiles all
examples; actual execution and output checks are separate.

`run-failure-handler` writes a non-fatal report by default. Pass
`-- --crash segv`, `-- --crash fatal`, or `-- --crash fatal-log` to terminate the
child process and inspect the crash file under the configured directory. Use
`-- --directory DIR` to choose a different directory.

Examples are selected and imported by the repository-root `examples.zig`, and
`@src().file` preserves the `examples/` prefix. Text prints
`source= examples/mmap.zig:line:column` without outer quotes; ordinary package
modules use `kron.source.fromModule` to map repository paths at compile time. See
[source location](../docs/usage.md#time-trace-and-source-location).
