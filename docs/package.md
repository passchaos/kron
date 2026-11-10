# Zig package integration

The library exposes only a Zig API. Consumer projects import the `kron` module
through a Zig package dependency and use their own allocator and `std.Io`; the
application build passes the target platform, optimization level, and threading
configuration.

Add a local dependency in the application's `build.zig.zon` (the path is relative
to the application package):

```zig
.dependencies = .{
    .kron = .{ .path = "../kron" },
},
```

Application `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const single = b.option(bool, "single-threaded", "Use synchronous single-threaded logging") orelse false;
    const kron = b.dependency("kron", .{
        .target = target,
        .optimize = optimize,
        .@"single-threaded" = single,
    });
    const app = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single,
    });
    app.addImport("kron", kron.module("kron"));
    b.installArtifact(b.addExecutable(.{ .name = "app", .root_module = app }));
}
```

`b.dependency` creates the library module; the application does not need to
build or run the library's own tools and tests. Android/Apple system-library
dependencies are expressed by the module, and the application still needs the
normal platform toolchain and sandbox file paths; see
[platforms.md](platforms.md) for compile and execution qualification.

In the example, the application module root is `src/main.zig`, so Zig's
`@src().file` is relative to `src/`. To emit repository-relative paths, use
`kron.source.fromModule("src", @src())` at the call site, or move the module entry
point to a repository-root `main.zig` that imports `src/main.zig`. Text prints an
unquoted `src/path.zig:line:column`; see
[source location](usage.md#time-trace-and-source-location) for complete steps.

## Application lifetime

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .outputs = &.{
            .{
                .target = .{
                    .file = .{
                        .path = "app.jsonl",
                        .backend = .portable,
                    },
                },
                .mode = .asynchronous,
                .format = .json,
            },
        },
    });
    defer logging.destroy();
    _ = try logging.scoped("app").tryEmit(.info, "started", .{ .version = @as(u32, 1) });
    try logging.shutdown();
}
```

`Logging` manages all configured outputs and the underlying Runtime resources.
The application stops all logger/token users, explicitly shuts down, destroys the
owner, and finally cleans up the application I/O environment. Shutdown errors
should be handled explicitly by the application; `defer` cleanup is not a
durable confirmation. For Mmap, set `.queue = .{ .mmap = journal_options }` on
each route; the two recovery semantics differ. See the
[detailed usage guide](usage.md) for all parameters, context/thread ownership,
and examples. Multiple outputs and rotation also use Logging; lower-level
extensions such as custom sinks and cross-generation recovery can still use
Runtime, destroyed in Runtime → sink order.

Single-threaded consumer projects use `-Dsingle-threaded=true`; Logging routes
default to `.mode = .sync`, Runtime uses `.submission = .sync`, and no
asynchronous queue is configured. Ordinary flush/shutdown are available;
async/SPSC and deadline-aware control interfaces return explicit capability
errors. The library module and application must pass consistent threading
configuration.

System local time is an explicit option: Linux applications add
`.@"system-local-time" = true` to the `b.dependency` arguments, or set
`.link_libc = true` on the application module, then configure
`.timestamp = .{ .zone = .local }`. The default fixed-offset path does not depend
on libc. See [time documentation](time.md#system-local-time) for conversion,
caching, and recovery-identity contracts.

## Independent consumer acceptance

`tests/package_consumer/` is a complete separate Zig package with its own
`build.zig`, `build.zig.zon`, and sources, importing the library through
`b.dependency("kron")`. `test-package` builds and actually runs sync, memory,
mmap, SPSC-memory, and SPSC-mmap, verifying written/pending, file counts, JSON
fields, timestamps, source-overwrite snapshots, and redaction.
`test-package-single-threaded` builds another single-threaded package and, on
Linux, verifies that only one OS thread exists and that asynchronous mode fails
before creating files.

```sh
zig build test-package -Doptimize=ReleaseSafe -j1
zig build test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-package-distribution -Doptimize=ReleaseSafe -j1
```

`test-package-distribution` constructs a source directory without generated
caches according to the library `build.zig.zon` `.paths`, uses Zig 0.16
`zig fetch` to create a content-addressed source archive, and safely extracts it
into an independent directory. A fresh consumer project depends only on the
extracted source and actually runs the same five modes. This catches modules that
exist in the development directory but are missing from the release package. The
gate uses only a local temporary directory, does not publish a package, and does
not access the network.

A local directory fetch does not automatically exclude ignored files from the
development workspace. The source package `.paths` includes only the library,
build support, benchmark sources/scripts, and documentation; measured benchmark
results and reference-implementation snapshots do not enter the package. Staging
checks still exclude caches, and after extraction verify that generated artifacts
did not enter the source package. A past run found about 3.8 GB of local
measurement artifacts causing a 30-second fetch timeout; that failure was
retained.

The 2026-10-31 ReleaseSafe source-package acceptance passed all five modes.
Package hashes, binary SHA-256, output SHA-256, and per-mode counts from that run
were recorded in its evidence, which is no longer tracked. Workspace dependency
and single-threaded consumption also passed. Package hashes correspond to the
source snapshot at test time; after documentation or source changes, rerun the
gate to produce a new snapshot.

Consumer applications can also run it directly:

```sh
cd tests/package_consumer
zig build run -Doptimize=ReleaseSafe -- memory /tmp/kron-consumer-memory
zig build run -Doptimize=ReleaseSafe -Dsingle-threaded=true -- sync /tmp/kron-consumer-sync
```

The test driver places generated caches in the repository's shared
`.zig-cache`, and the consumer fixture keeps only source files. Reports record
the host platform, actual Zig version, source-file SHA-256, binary and output
SHA-256; source-distribution mode also records the Zig package hash and archive
SHA-256. Generating and linking a Windows PE with an independent consumer is
build evidence; this host has no Windows/Apple/Android device, so a link result
is not execution verification.

## Target-platform self-check

The consumer application adds a `qualify DIRECTORY` mode that uses its own
allocator and `std.Io` to run tests and emit a JSON report. It needs no Python or
subprocess at runtime; the `test-platform-host` Python driver only compiles,
starts, and records results.

```sh
zig build test-platform-host -Doptimize=ReleaseSafe -j1
cd tests/package_consumer
zig build run -Doptimize=ReleaseSafe -- qualify /tmp/kron-host-check
```

Windows example:

```powershell
.\kron-package-consumer.exe qualify C:\kron-host-check
```

The path should be on the writable disk being qualified. The test creates only
`DIRECTORY/native-check`; if it already exists, the test returns an error and
preserves the existing results without cleaning or overwriting logs. Generated
Unicode file names, per-mode output, journals, and rotation archives are
available for manual inspection.

Android/iOS Zig hosts can compile `tests/package_consumer/platform.zig` as a test
module, add a `kron` import, and call `run(allocator, io, sandbox_directory)`. The
function returns a structured `Report`, and the host chooses how to display or
store it. Test files are not part of the production public API and do not create
platform GUIs, C interfaces, or other language bridges. Mobile file paths and
`std.Io` lifetime are the host's responsibility.

Acceptance covers five runtime modes (single-threaded only sync), zero Runtime
allocation after initialization, filter reload, string/nested snapshots,
redaction, flush/shutdown/deadline capabilities, Unicode file paths, ordinary
and schema journal exclusive locking/close-reopen/read-only inspection, rotation
retention, and actual durable results. `confirmed` in the report means the
synchronous protocol call succeeded; `unsupported` is a specific filesystem or
platform capability rejection; other I/O errors fail the test. Close-reopen is
not equivalent to a forced kill or power-loss qualification.
