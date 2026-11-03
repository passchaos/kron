#!/usr/bin/env python3
"""Pinned local C++/kron comparison with full file record verification."""
import argparse
import collections
import hashlib
import json
import os
import pathlib
import platform
import re
import statistics
import subprocess
import shutil
import tarfile
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def tree_sha256(directory):
    digest = hashlib.sha256()
    for file in sorted(pathlib.Path(directory).rglob("*")):
        if file.is_file():
            digest.update(str(file.relative_to(directory)).encode() + b"\0")
            digest.update(file.read_bytes())
    return digest.hexdigest()


def command_metadata(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        return {"command": command, "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": command, "available": False, "error": str(error)}


def dependencies(name, pin, directory):
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / f"{name}-{pin['tag']}.tar.gz"
    source = directory / pin["directory"]
    if not archive.exists():
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                        "--connect-timeout", "10", "--max-time", "60", pin["url"],
                        "--output", str(archive)], check=True, timeout=65)
    actual = sha256(archive)
    if actual != pin["sha256"]:
        raise RuntimeError(f"{name} archive checksum mismatch: {actual}")
    if not source.exists():
        with tarfile.open(archive) as bundle:
            bundle.extractall(directory, filter="data")
    return source, {**pin, "archive": str(archive), "archive_sha256_verified": actual,
                    "source_directory": str(source), "compiled_include_tree_sha256": tree_sha256(source / "include")}


def build(name, source, output, compiler, zig):
    binary = output / f"reference-{name}"
    if name == "kron":
        command = [zig, "build-exe", "-O", "ReleaseFast", "--dep", "kron",
                   f"-Mroot={HERE / 'kron_reference.zig'}", "-O", "ReleaseFast",
                   f"-Mkron={ROOT / 'src/root.zig'}", f"-femit-bin={binary}"]
    else:
        command = [compiler, "-std=c++17", "-O3", "-DNDEBUG", "-pthread",
                   f"-DLIB_{name.upper()}", f"-I{source / 'include'}",
                   str(HERE / "reference.cpp"), "-o", str(binary)]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    record = {"command": command, "returncode": result.returncode, "stderr": result.stderr}
    if result.returncode != 0:
        return None, record
    record["binary_sha256"] = sha256(binary)
    return binary, record


def foundation_snapshot(root, output):
    # Freeze the requested local owning sources; never write into that repo.
    original = pathlib.Path(root).expanduser().resolve(strict=True)
    source = output / "foundation-source"
    for name in ("cpp", "rust"):
        shutil.copytree(original / name, source / name,
                        ignore=shutil.ignore_patterns("target", "__pycache__"), dirs_exist_ok=True)
    shutil.copyfile(HERE / "foundation_tracing_reference.rs", source / "rust/src/bin/kron_tracing_reference.rs")
    return original, source


def build_foundation(root, output, dependencies_dir, compiler, cargo, spdlog):
    original, source = foundation_snapshot(root, output)
    target = dependencies_dir / "foundation-target"
    rust_command = [cargo, "build", "--release", "--locked", "--lib", "-j1",
                    "--manifest-path", str(source / "rust/Cargo.toml"), "--target-dir", str(target)]
    compiled = subprocess.run(rust_command, capture_output=True, text=True, timeout=180)
    if compiled.returncode != 0:
        raise RuntimeError(f"Foundation Rust build failed: {compiled.stderr}")
    binary = output / "reference-foundation"
    command = [compiler, "-std=c++17", "-O3", "-DNDEBUG", "-pthread", "-DLIB_FOUNDATION",
               f"-I{spdlog / 'include'}", f"-I{source / 'cpp/include'}",
               str(HERE / "reference.cpp"), str(source / "cpp/src/logger.cc"),
               str(target / "release/libfoundation_logging_core.a"), "-ldl", "-lm", "-o", str(binary)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        raise RuntimeError(f"Foundation C++ build failed: {result.stderr}")
    return binary, {"command": command, "rust_command": rust_command, "rust_stderr": compiled.stderr,
                    "returncode": 0, "binary_sha256": sha256(binary), "source_origin": str(original),
                    "snapshot": str(source), "snapshot_tree_sha256": tree_sha256(source),
                    "rust_static_sha256": sha256(target / "release/libfoundation_logging_core.a"),
                    "cargo": command_metadata([cargo, "--version"]), "rustc": command_metadata(["rustc", "--version"])}


def build_foundation_tracing(root, output, dependencies_dir, cargo):
    original, source = foundation_snapshot(root, output)
    target = dependencies_dir / "foundation-target"
    command = [cargo, "build", "--release", "--locked", "--bin", "kron_tracing_reference", "-j1",
               "--manifest-path", str(source / "rust/Cargo.toml"), "--target-dir", str(target)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    if result.returncode != 0:
        raise RuntimeError(f"Foundation tracing build failed: {result.stderr}")
    binary = output / "reference-foundation_tracing"
    shutil.copyfile(target / "release/kron_tracing_reference", binary)
    binary.chmod(0o755)
    return binary, {"command": command, "stderr": result.stderr, "returncode": 0,
                    "binary_sha256": sha256(binary), "source_origin": str(original),
                    "snapshot": str(source), "snapshot_tree_sha256": tree_sha256(source),
                    "benchmark_source_sha256": sha256(HERE / "foundation_tracing_reference.rs"),
                    "cargo": command_metadata([cargo, "--version"]), "rustc": command_metadata(["rustc", "--version"])}


def verify(row, artifact, events, warmup):
    assert row.get("metadata") in {"minimal", "full", "default_text", "native_tracing"}
    if row.get("metadata") == "native_tracing":
        assert row["library"] == "foundation_tracing"
    assert row["status"] == "ok" and row["events"] == events, row
    assert row["warmup_events"] == warmup and row["queue_policy"] == "block" and row["file_buffer_bytes"] == 65536
    if row["library"] in {"foundation", "foundation_tracing"}:
        assert row["foundation_submitted_records"] == row["foundation_written_records"] == events + warmup
        assert row["has_process_crash_recovery"] is (row["storage"] == "mmap")
    if row["library"] == "kron":
        assert row["has_process_crash_recovery"] is (row["storage"] == "mmap")
        assert row["journal_reserved_bytes"] == (0 if row["storage"] == "memory" else row["queue_reserved_bytes"])
    assert row["accepted"] == row["written"] == events and row["drop"] == row["final_pending"] == 0, row
    assert row["total_ns"] >= row["producer_wall_ns"] + row["flush_ns"] + row["shutdown_ns"], row
    if row.get("schema_version") == 2:
        assert row["total_ns"] == sum(row[key] for key in ("producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns")), row
        assert row["lifecycle_ns"] == row["init_ns"] + row["preparation_ns"] + row["total_ns"], row
        assert all(isinstance(row[key], int) and row[key] >= 0 for key in ("total_ns", "init_ns", "preparation_ns", "cleanup_ns")), row
        assert row["total_ns"] > 0
        assert abs(row["written_records_per_sec"] - events * 1e9 / row["total_ns"]) < 0.01
    assert row["sample_count"] == (events if row["phase"] == "sampled" else 0), row
    if row["phase"] == "sampled":
        assert row["p50_ns"] <= row["p99_ns"] <= row["p999_ns"], row
    else:
        assert row["p50_ns"] is None and row["p99_ns"] is None and row["p999_ns"] is None, row
    contents = artifact.read_bytes()
    assert len(contents) == row["artifact_bytes"], row
    if row["library"] in {"foundation", "foundation_tracing"}:
        assert row["foundation_written_bytes"] == len(contents)
    assert contents.endswith(b"\n") and contents.count(b"\n") == events + warmup, row
    seen = set()
    identities = set()
    warmup_bytes = 0
    for line in contents.splitlines(keepends=True):
        if row.get("metadata") == "native_tracing":
            text = line.decode("utf-8")
            assert "\x1b" not in text and " INFO " in text and "event" in text, text
            fields = re.findall(r"\bfield([0-4])=(\d+)(?=\s|$)", text)
            assert len(fields) == 5 and len({key for key, _ in fields}) == 5, text
            attrs = {f"field{key}": int(value) for key, value in fields}
            event = {"message": "event", "attributes": attrs}
        else:
            decoded_line = line[line.index(b'{"message":"event"'):] if row.get("metadata") == "default_text" else line
            if row.get("metadata") == "default_text":
                assert b" [info] [reference] [thread " in line[:line.index(b'{"message":"event"')]
            event = json.loads(decoded_line)
        assert event["message"] == "event", event
        attrs = event["attributes"]
        assert set(attrs) == {f"field{i}" for i in range(5)}, event
        n = int(attrs["field0"])
        assert 0 <= n < events + warmup and n not in seen, event
        assert all(int(attrs[f"field{i}"]) == n + i for i in range(5)), event
        if row.get("metadata") == "full":
            assert set(event) == {"timestamp_ns", "severity", "scope", "message", "session", "channel", "sequence", "route_mask", "config_generation", "trace_flags", "attributes"}, event
            assert isinstance(event["timestamp_ns"], str) and event["timestamp_ns"].isascii() and event["timestamp_ns"].isdigit() and len(event["timestamp_ns"]) == 19, event
            assert event["severity"] == "info" and event["scope"] == "reference", event
            assert event["session"] == "18446744073709551615" and event["route_mask"] == event["config_generation"] == 1 and event["trace_flags"] == 0, event
            identity = (int(event["channel"]), int(event["sequence"]))
            assert identity[1] > 0 and identity not in identities, event
            identities.add(identity)
        seen.add(n)
        if n >= events:
            warmup_bytes += len(line)
    assert seen == set(range(events + warmup)), row
    assert len(contents) - warmup_bytes == row["written_bytes"], row
    row["file_records_verified"] = len(seen)
    row["file_sha256"] = hashlib.sha256(contents).hexdigest()
    row["written_mib_per_sec"] = row["written_bytes"] * 1e9 / row["total_ns"] / 1048576


def affinity(value):
    allowed = sorted(os.sched_getaffinity(0))
    if value == "none":
        return allowed
    if value != "auto":
        chosen = sorted(set(map(int, value.split(","))))
        if not chosen or not set(chosen) <= set(allowed):
            raise ValueError("affinity must be a nonempty subset of currently allowed CPUs")
        return chosen
    chosen, cores = [], set()
    for cpu in allowed:
        topology = pathlib.Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
        key = tuple((topology / name).read_text().strip() for name in ("physical_package_id", "core_id"))
        if key in cores:
            continue
        cores.add(key)
        chosen.append(cpu)
        if len(chosen) == 6:
            break
    return chosen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deps-dir", default=str(ROOT / ".zig-cache/bench-deps"))
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--libraries", default="spdlog,quill,kron")
    parser.add_argument("--events", type=int, default=10000)
    parser.add_argument("--warmup", type=int, default=1000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--producers", default="1,4")
    parser.add_argument("--timeout-seconds", type=int, default=45)
    parser.add_argument("--compiler", default="c++")
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--kron-frontend", choices=("runtime", "managed"), default="runtime")
    parser.add_argument("--kron-modes", default="async,spsc")
    parser.add_argument("--kron-storages", default="memory,mmap")
    parser.add_argument("--kron-schema", choices=("off", "on", "both"), default="off")
    parser.add_argument("--kron-render-cache", action="store_true")
    parser.add_argument("--metadata", choices=("minimal", "full", "default_text", "native_tracing"), default="full")
    parser.add_argument("--affinity", default="auto")
    parser.add_argument("--discard-artifacts", action="store_true")
    parser.add_argument("--foundation-root", default="~/robotics/onboard-monorepo/foundation/logging")
    parser.add_argument("--cargo", default="cargo")
    options = parser.parse_args()
    libraries = options.libraries.split(",")
    producers = [int(p) for p in options.producers.split(",")]
    modes = options.kron_modes.split(",")
    storages = options.kron_storages.split(",")
    if (not set(libraries) <= {"spdlog", "quill", "kron", "foundation", "foundation_tracing"} or not set(producers) <= {1, 4}
            or not set(modes) <= {"async", "spsc"} or not set(storages) <= {"memory", "mmap"} or not 1 <= options.events <= 1000000
            or not 0 <= options.warmup <= 1000000 or not 1 <= options.repeats <= 10
            or not 1 <= options.timeout_seconds <= 120):
        parser.error("invalid bounded comparison options")
    if any(not values or len(set(values)) != len(values) for values in (libraries, producers, modes, storages)):
        parser.error("comparison lists must be nonempty and contain no duplicates")
    if options.metadata == "default_text" and libraries != ["foundation"]:
        parser.error("default_text is a separate Foundation-only control; other references use the common full JSON workload")
    if options.metadata == "native_tracing" and libraries != ["foundation_tracing"]:
        parser.error("native_tracing is a separate standard tracing-only control")
    chosen_cpus = affinity(options.affinity)
    output = pathlib.Path(options.output_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    artifacts = output / "artifacts"
    artifacts.mkdir(exist_ok=True)
    pins = json.loads((HERE / "versions.json").read_text())
    manifest = {
        "captured_unix_seconds": time.time(), "host": dict(platform.uname()._asdict()),
        "loadavg_before": os.getloadavg(),
        "logical_cpus": os.cpu_count(), "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
        "child_affinity": chosen_cpus, "configuration": vars(options),
        "compiler": command_metadata([options.compiler, "--version"]), "zig": command_metadata([options.zig, "version"]),
        "filesystem": command_metadata(["findmnt", "-T", str(output), "-o", "SOURCE,FSTYPE,OPTIONS", "--json"]),
        "cpu_topology": command_metadata(["lscpu", "--json"]),
        "dependencies": {}, "builds": {}, "source_sha256": {name: sha256(HERE / name) for name in ("reference.cpp", "kron_reference.zig", "foundation_tracing_reference.rs", "versions.json", "run.py", "analyze.py", "qualification.py")},
        "notes": ["Identical logical event and five numeric attributes; kron adds structured event metadata.",
                  "C++ volatile queues lack mmap process-crash recovery; these results are not a universal ranking.",
                  "Queue bounds use different units and include separately reported backend transit storage."]}
    if {"foundation", "foundation_tracing"}.intersection(libraries):
        foundation_directory = pathlib.Path(options.foundation_root).expanduser().resolve()
        manifest["foundation_repository"] = command_metadata(["git", "-C", str(foundation_directory), "rev-parse", "HEAD"])
    manifest["production_source_sha256"] = {str(file.relative_to(ROOT)): sha256(file) for file in sorted((ROOT / "src").rglob("*.zig"))}
    if options.metadata == "full":
        manifest["notes"][0] = "Same full JSON metadata/attributes layout and system wall-clock domain; timestamp values and channel/sequence allocation differ."
    if options.metadata == "native_tracing":
        manifest["notes"][0] = "Native Foundation build_tracing text control; not interchangeable with the common full JSON workload."
    manifest["notes"].append("Managed kron SPSC uses its native spin idle policy; legacy Runtime benchmark explicitly sleeps. Row consumer_idle records the selected policy.")
    manifest["notes"].append("Foundation tracing full JSON uses the public TracingMakeWriter with an event formatter; native_tracing uses unmodified build_tracing and its private optimized fmt writer.")
    binaries = {}
    incomplete = False
    for name in libraries:
        try:
            source = None
            if name == "foundation":
                spdlog, dependency = dependencies("spdlog", pins["spdlog"], pathlib.Path(options.deps_dir).resolve())
                manifest["dependencies"]["foundation-spdlog"] = dependency
                binary, record = build_foundation(options.foundation_root, output, pathlib.Path(options.deps_dir).resolve(), options.compiler, options.cargo, spdlog)
            elif name == "foundation_tracing":
                binary, record = build_foundation_tracing(options.foundation_root, output, pathlib.Path(options.deps_dir).resolve(), options.cargo)
            elif name != "kron":
                source, dependency = dependencies(name, pins[name], pathlib.Path(options.deps_dir).resolve())
                manifest["dependencies"][name] = dependency
                binary, record = build(name, source, output, options.compiler, options.zig)
            else:
                binary, record = build(name, source, output, options.compiler, options.zig)
            manifest["builds"][name] = record
            if binary is not None:
                binaries[name] = binary
                print(f"{name}: built local pinned reference", flush=True)
            else:
                incomplete = True
                print(f"{name}: build failed; continuing independent libraries", flush=True)
        except (OSError, subprocess.SubprocessError, RuntimeError) as error:
            manifest["builds"][name] = {"status": "failed", "error": str(error)}
            incomplete = True
            print(f"{name}: unavailable ({error}); continuing", flush=True)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    cases = []
    for name in binaries:
        strategies = (storages if name in {"foundation", "foundation_tracing"} else ["producer_format", "deferred_format"] if name == "quill" else ([f"{mode}-{storage}-{'schema' if schema else 'inline'}" for mode in modes for storage in storages for schema in ((False, True) if options.kron_schema == "both" else (options.kron_schema == "on",))] if name == "kron" else ["producer_format"]))
        for strategy in strategies:
            for producer in producers:
                for phase in ("sampled", "batch"):
                    cases.append((name, strategy, producer, phase))
    rows = []
    timed_out_libraries = set()
    with (output / "results.jsonl").open("w") as evidence:
        for repetition in range(options.repeats):
            ordered = list(reversed(cases)) if repetition % 2 else cases
            order = ordered[repetition % len(ordered):] + ordered[:repetition % len(ordered)] if ordered else []
            for name, strategy, producer, phase in order:
                artifact = artifacts / f"{name}-{strategy}-p{producer}-{phase}-r{repetition}.jsonl"
                command = [str(binaries[name]), f"--output={artifact}", f"--events={options.events}", f"--warmup={options.warmup}",
                           f"--producers={producer}", f"--phase={phase}", "--queue-slots=256",
                           *([f"--frontend={options.kron_frontend}", f"--mode={strategy.split('-')[0]}", f"--storage={strategy.split('-')[1]}", f"--schema={str(strategy.endswith('-schema')).lower()}", *(["--render-cache=true"] if options.kron_render_cache and producer == 4 else [])] if name == "kron" else ["--strategy=producer_format", f"--storage={strategy}", f"--metadata={options.metadata}"] if name in {"foundation", "foundation_tracing"} else [f"--strategy={strategy}", f"--metadata={options.metadata}"])]
                row = {"status": "failed", "library": name, "strategy": strategy, "phase": phase,
                       "producers": producer, "repetition": repetition, "command": command, "artifact": str(artifact)}
                if name in timed_out_libraries:
                    row.update({"status": "skipped_after_library_timeout", "retry_started": False})
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                    continue
                try:
                    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=options.timeout_seconds,
                                            preexec_fn=lambda: os.sched_setaffinity(0, chosen_cpus))
                    if result.returncode != 0:
                        row.update({"error": "nonzero_exit", "returncode": result.returncode, "stderr": result.stderr, "stdout": result.stdout})
                        incomplete = True
                    else:
                        parsed = json.loads(result.stdout)
                        row.update(parsed)
                        row["case"] = strategy
                        row["child_affinity"] = chosen_cpus
                        verify(row, artifact, options.events, options.warmup)
                        assert row["phase"] == phase and row["producers"] == producer and row["library"] == name
                        print(f"{name}/{strategy} p{producer} {phase}: {row['written']} complete records", flush=True)
                except subprocess.TimeoutExpired as error:
                    row.update({"status": "incomplete_timeout", "timeout_seconds": options.timeout_seconds,
                                "stdout_before_timeout": (error.stdout or b"").decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout,
                                "retry_started": False})
                    incomplete = True
                    timed_out_libraries.add(name)
                    print(f"{name}/{strategy}: timeout; retained artifact, no retry", flush=True)
                except (AssertionError, json.JSONDecodeError, OSError) as error:
                    row.update({"status": "failed_validation", "error": str(error)})
                    incomplete = True
                evidence.write(json.dumps(row) + "\n")
                evidence.flush()
                rows.append(row)
                if options.discard_artifacts and row["status"] == "ok":
                    artifact.unlink()
                    for journal in artifacts.glob(artifact.name + "*.journal"):
                        journal.unlink()
                    for spool in artifacts.glob(artifact.name + "*.spool"):
                        spool.unlink()
    manifest["loadavg_after"] = os.getloadavg()
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    groups = collections.defaultdict(list)
    for row in rows:
        if row["status"] == "ok":
            groups[(row["library"], row.get("case", row.get("mode", row["strategy"])), row["producers"], row["phase"])].append(row)
    summary = {}
    for key, selected in groups.items():
        rates = [row["written_records_per_sec"] for row in selected]
        summary["/".join(map(str, key))] = {
            "trials": len(selected), "written_records_per_sec_median": statistics.median(rates),
            "written_records_per_sec_min": min(rates), "written_records_per_sec_max": max(rates),
            "producer_p50_ns_median": statistics.median(row["p50_ns"] for row in selected) if key[-1] == "sampled" else None,
            "producer_p99_ns_median": statistics.median(row["p99_ns"] for row in selected) if key[-1] == "sampled" else None,
            "producer_p999_ns_median": statistics.median(row["p999_ns"] for row in selected) if key[-1] == "sampled" else None,
            "has_process_crash_recovery": selected[0]["has_process_crash_recovery"]}
        for metric in ("producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns", "init_ns", "preparation_ns", "total_ns", "lifecycle_ns", "lifecycle_records_per_sec", "written_mib_per_sec"):
            summary["/".join(map(str, key))][metric + "_median"] = statistics.median(row[metric] for row in selected)
        median = statistics.median(rates)
        summary["/".join(map(str, key))]["throughput_relative_spread"] = (max(rates) - min(rates)) / median
        summary["/".join(map(str, key))]["performance_qualification"] = "inconclusive" if len(rates) < 5 or (max(rates) - min(rates)) / median > .10 else "local_repeatability_within_10_percent"
        if key[-1] == "sampled":
            for metric in ("p50_ns", "p99_ns", "p999_ns"):
                values = [row[metric] for row in selected]
                summary["/".join(map(str, key))][metric + "_relative_spread"] = (max(values) - min(values)) / statistics.median(values)
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 2 if incomplete else 0


if __name__ == "__main__":
    raise SystemExit(main())
