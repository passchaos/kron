# kron

A native Zig 0.16 logging library with structured fields, synchronous and
bounded asynchronous submission, plain text and JSON output, file rotation,
dynamic filtering and configuration, redaction, archives, and explicit recovery
boundaries. The goal is to keep application overhead low, keep output readable,
and make reliability boundaries testable.

The library keeps its default CRC, full value-domain, recovery, and bounded
queue contracts. Recent optimization candidates produced local workload wins,
but did not qualify for retention under control groups or complete workflows;
production paths were restored and the corresponding boundary regressions were
kept. See [current acceptance status](docs/implementation-status.md) and the
[experiment snapshot](docs/history/readme-performance-experiments-2026-11-03.md)
for positive, negative, and limited results.

Applications start from **`kron.Logging`**. The default is stderr, synchronous,
text, info level. Single-file, multiple-output, rotating, Memory/Mmap, and SPSC
configurations share the same initialization, logger acquisition, and shutdown
methods.

See [current acceptance status](docs/implementation-status.md) and the
[performance snapshot](docs/history/readme-performance-2026-11-09.md) for the
current performance conclusions and latest verification.

## Quick start

Import the module in an application build through `b.dependency("kron")`. See
[Zig package integration](docs/package.md) for the complete configuration. A
minimal program:

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    logging.scoped("app").info("started", .{ .version = "1.0" });
    try logging.shutdown();
}
```

For background file logging, set the `create` options to:

```zig
.{
    .outputs = &.{.{
        .name = "file",
        .target = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
        .mode = .asynchronous,
        .format = .json,
    }},
}
```

The asynchronous queue defaults to bounded Memory. System local time can be
selected per route with `.timestamp = .{ .zone = .local }`; on Linux this
requires explicit libc support. Source locations carrying `At` use
repository-relative paths, and text output prints them as unquoted
`path:line:column`. Outputs always use the `outputs` list; mode, queue,
overflow, redaction, sampling, and similar settings are configured per route,
and omitted fields take the route defaults. See the [usage guide](docs/usage.md)
for complete parameters, context, threads, multiple outputs, `std.log`, and
shutdown error handling. Runnable sources are under [examples/](examples/README.md).

## Modes and completion boundaries

| Choice | Suitable scenario | Contract |
| --- | --- | --- |
| sync | Small tools, single-threaded, low log rate | The calling thread performs encoding and delivery |
| shared Memory | Ordinary background logging | Bounded shared queue; records not yet delivered are lost on abnormal process exit |
| shared Mmap | Process-crash recovery required | Complete commits are recovered, with at-least-once replay allowed |
| SPSC Memory/Mmap | Advanced opt-in: fixed threads and verified application benefit | Explicit attach/detach; per-thread queues and an ordinary shared queue are preallocated |

`flush()` confirms that required outputs are written, `flushDurable()` requests
the durable protocol for applicable outputs and journals, and `shutdown()`
closes admission and drains. Accepted, written, and durable are distinct;
an Mmap commit is not a power-loss guarantee. See
[asynchronous storage](docs/async-storage.md), [lifecycle](docs/lifecycle.md),
and [file reliability](docs/file-reliability.md) for the detailed protocols.

File output supports the portable backend and the Linux io_uring backend.
Network sinks and exporters are outside the current single-machine scope.

## Documentation map

| Purpose | Documents |
| --- | --- |
| Get started, find parameters and lifecycle rules | [Usage guide](docs/usage.md), [package integration](docs/package.md), [default integration advice](docs/default-logging.md) |
| Understand the API and internals | [API architecture](docs/api-design.md), [code structure](docs/code-structure.md), [overall design](docs/design.md) |
| Modify sources, choose tests, maintain evidence | [Development and verification](docs/development.md), [test directory](tests/README.md), [benchmark directory](bench/README.md) |
| Check capabilities, platforms, and remaining work | [Capability matrix](docs/capability-matrix.md), [current acceptance status](docs/implementation-status.md), [platform support](docs/platforms.md) |
| Capture fatal-signal and fatal-event crashes | [Failure handler](docs/failure-handler.md) |
| Browse all topics and historical records | [Documentation navigation](docs/README.md), [history](docs/history/README.md) |
| Check versions and recent changes | [Changelog](CHANGELOG.md) |

## Build and examples

```sh
zig build
zig build run-quick-start
zig build run-file-logging
zig build run-rolling
zig build run-local-time
zig build run-file-stdout-local-time
zig build run-mmap
zig build run-source-location
zig build run-route-policies
zig build test-unit -Doptimize=ReleaseSafe -j1
zig build test-logging -Doptimize=ReleaseSafe -j1
zig build test-failure-handler -Doptimize=ReleaseSafe -j1
zig build verify-fast -Doptimize=ReleaseSafe -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build fmt hygiene links -j1
zig build docs -j1
```

`zig build` installs `kroncat` and `kron-bench`; dependency consumers import
only the library module. `verify-local` covers unit and integration tests,
negative compilation, real SIGKILL recovery, an independent package consumer,
single-threaded builds, and tool/example compilation. Source distribution is
verified separately with `test-package-distribution`. See
[development and verification](docs/development.md) for the complete command
set selected by change scope.

```sh
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
```

See [tools/](tools/README.md) for tool usage.

## Performance and release scope

The current capability targets Linux single-machine projects pinned to Zig
0.16. Start with bounded Memory and the portable backend, and handle overload
and shutdown errors in the application. Windows, macOS, Android, and iOS have
implementations and cross-compilation or partial-link evidence, but still need
real-device qualification. The package version is 0.1.0.

The repository keeps its own Zig benchmark harnesses and analysis scripts under
`bench/`. Cross-library C++/Rust comparison harnesses, frozen reference source
snapshots, and measured result directories have been removed; the current
status and historical summaries remain in
[current acceptance status](docs/implementation-status.md) and
[history](docs/history/README.md). Current conclusions: durable memory is
largely ahead of the previous comparison baseline, while the remaining gap is
concentrated in P1 mmap versus tracing. `text_format`, `MmapSpool`, and
`render_cache` are opt-in fast paths; the default durable/CRC/recovery/queue
contracts are unchanged.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE).
