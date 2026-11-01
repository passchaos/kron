#!/usr/bin/env python3
"""Build an independent Zig dependency consumer and verify its local outputs."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import tempfile
import tarfile


MODES = ("sync", "memory", "mmap", "spsc_memory", "spsc_mmap")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--optimize", choices=("Debug", "ReleaseSafe", "ReleaseFast"), default="ReleaseSafe")
    parser.add_argument("--report", type=pathlib.Path)
    parser.add_argument("--single-threaded", action="store_true")
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--platform-only", action="store_true")
    args = parser.parse_args()
    version = subprocess.run([args.zig, "version"], capture_output=True, text=True, timeout=10)
    assert version.returncode == 0, (version.stdout, version.stderr)
    root = pathlib.Path(__file__).resolve().parents[1]
    fixture = root / "tests/package_consumer"
    results = []
    with tempfile.TemporaryDirectory(prefix="kron-zig-package-") as temporary:
        folder = pathlib.Path(temporary)
        package_hash = None
        archive_hash = None
        distribution_paths = None
        global_cache = None
        if args.packaged:
            # Stage the declared distribution roots before local zig fetch.
            # Fetching a live directory can scan a large development cache.
            manifest = (root / "build.zig.zon").read_text()
            declaration = re.search(r"\.paths\s*=\s*\.\{([^}]*)\}", manifest)
            assert declaration, "missing distribution paths"
            paths = re.findall(r'"([^"]+)"', declaration.group(1))
            distribution_paths = paths
            stage = folder / "package"
            stage.mkdir()
            for relative in paths:
                source = root / relative
                destination = stage / relative
                if source.is_dir():
                    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".zig-cache", "zig-out", "__pycache__", "*.pyc"))
                else:
                    shutil.copy2(source, destination)
            global_cache = folder / "global-cache"
            fetched = subprocess.run([args.zig, "fetch", "--global-cache-dir", str(global_cache), str(stage)],
                                     capture_output=True, text=True, timeout=30)
            assert fetched.returncode == 0, (fetched.stdout, fetched.stderr)
            package_hash = fetched.stdout.strip()
            archive = global_cache / "p" / (package_hash + ".tar.gz")
            assert archive.is_file(), "missing fetched source archive"
            archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
            unpacked = folder / "unpacked"
            unpacked.mkdir()
            with tarfile.open(archive, "r:gz") as contents:
                contents.extractall(unpacked, filter="data")
            package = unpacked / package_hash
            assert (package / "src/root.zig").is_file(), "missing module in fetched package"
            assert not list(package.rglob(".zig-cache")) and not list(package.rglob("zig-out")), "generated output entered package"
            fixture = folder / "consumer"
            shutil.copytree(root / "tests/package_consumer", fixture)
            consumer_manifest = fixture / "build.zig.zon"
            dependency_path = pathlib.Path("..") / package.relative_to(folder)
            consumer_manifest.write_text(consumer_manifest.read_text().replace('"../.."', json.dumps(dependency_path.as_posix())))
        prefix = folder / "install"
        command = [args.zig, "build", f"-Doptimize={args.optimize}", "-j1", "--prefix", str(prefix),
                   "--cache-dir", str(root / ".zig-cache/package-consumer")]
        if args.single_threaded:
            command.append("-Dsingle-threaded=true")
        if global_cache:
            command.extend(("--global-cache-dir", str(global_cache)))
        build = subprocess.run(command, cwd=fixture, capture_output=True, text=True, timeout=120)
        assert build.returncode == 0, (command, build.stdout, build.stderr)
        executable = prefix / "bin" / ("kron-package-consumer.exe" if os.name == "nt" else "kron-package-consumer")
        binary_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
        for mode in (() if args.platform_only else ("sync",) if args.single_threaded else MODES):
            output = folder / mode
            run = subprocess.run([str(executable), mode, str(output)], capture_output=True, text=True, timeout=30)
            assert run.returncode == 0, (mode, run.stdout, run.stderr)
            health = json.loads(run.stdout)
            expected_storage = "none" if mode == "sync" else "memory" if "memory" in mode else "mmap"
            assert health["mode"] == mode and health["storage"] == expected_storage, health
            assert health["single_threaded"] is args.single_threaded, health
            if args.single_threaded and platform.system() == "Linux":
                assert health["thread_count"] == 1, health
            else:
                assert health["thread_count"] is None, health
            assert health["accepted"] == health["written"] == 2 and health["pending"] == 0, health
            if expected_storage == "none":
                assert health["queue_bytes"] == health["mapped_bytes"] == 0
            elif expected_storage == "memory":
                assert health["queue_bytes"] > 0 and health["mapped_bytes"] == 0
            else:
                assert health["queue_bytes"] == health["mapped_bytes"] > 0
            payload = (output / "events.jsonl").read_bytes()
            assert b"private" not in payload and b"never captured" not in payload
            events = [json.loads(line) for line in payload.splitlines()]
            assert len(events) == 2
            first, second = events
            assert first["scope"] == second["scope"] == "consumer"
            assert first["message"] == "first" and first["severity"] == "info"
            assert first["attributes"] == {"service": "package-consumer", "id": 1, "nested": ["original", "[REDACTED]"], "password": "[REDACTED]"}
            assert second["message"] == "second 7" and second["severity"] == "debug"
            assert second["attributes"] == {"service": "package-consumer", "id": 2, "password": "[REDACTED]"}
            assert all(int(event["timestamp_ns"]) > 0 for event in events)
            journals = sorted(output.glob("*.journal"))
            assert len(journals) == (2 if mode == "spsc_mmap" else 1 if mode == "mmap" else 0), journals
            for journal in journals:
                image = journal.read_bytes()
                assert image.startswith(b"KRONJNL1")
                assert b"private" not in image and b"never captured" not in image
            results.append({"mode": mode, "health": health, "records": len(events), "journal_files": len(journals), "output_sha256": hashlib.sha256(payload).hexdigest()})
            print(f"Zig package consumer {mode}: 2 written, pending=0, journal_files={len(journals)}, source snapshots and redaction verified", flush=True)
        if args.single_threaded and not args.platform_only:
            for mode in MODES[1:]:
                output = folder / mode
                rejected = subprocess.run([str(executable), mode, str(output)], capture_output=True, text=True, timeout=10)
                assert rejected.returncode != 0 and "ThreadsUnavailable" in rejected.stderr, (mode, rejected.stderr)
                assert not output.exists(), "unsupported mode touched the filesystem"
            thread_evidence = "one OS thread verified through /proc; " if results[0]["health"]["thread_count"] == 1 else ""
            print(f"Independent single-threaded consumer: {thread_evidence}async modes rejected before file creation", flush=True)
        qualification = None
        if args.platform_only:
            run = subprocess.run([str(executable), "qualify", str(folder / "qualification")], capture_output=True, text=True, timeout=30)
            assert run.returncode == 0, (run.stdout, run.stderr)
            qualification = json.loads(run.stdout)
            assert qualification["single_threaded"] is args.single_threaded
            assert qualification["zig"] == version.stdout.strip() and qualification["optimize"] == args.optimize
            expected_modes = ("sync",) if args.single_threaded else MODES
            actual_modes = [entry for entry in qualification["modes"] if entry is not None]
            assert [entry["mode"] for entry in actual_modes] == list(expected_modes)
            for entry in actual_modes:
                assert entry["accepted"] == entry["written"] == 2 and entry["pending"] == entry["runtime_allocations_after_setup"] == 0
                assert entry["file_durable"] in ("confirmed", "unsupported")
                assert entry["storage"] == ("none" if entry["mode"] == "sync" else "memory" if "memory" in entry["mode"] else "mmap")
            assert [entry["schema"] for entry in qualification["journals"]] == [False, True]
            assert all(entry["recovered"] == 1 and entry["inspection_unchanged"] is True and entry["durable"] in ("confirmed", "unsupported") for entry in qualification["journals"])
            assert qualification["rolling_archives"] == 2 and qualification["rolling_durable"] in ("confirmed", "unsupported")
            if qualification["target"] == "windows":
                assert all(entry["file_durable"] == "unsupported" for entry in actual_modes)
                assert all(entry["durable"] == "unsupported" for entry in qualification["journals"])
                assert qualification["rolling_durable"] == "unsupported"
            print(f"Native Zig platform qualification {qualification['target']}: {len(actual_modes)} runtime modes, inline/schema journal reopen, rolling retention and explicit durability verified", flush=True)
        source_root = package if args.packaged else root
        source_hashes = {
            relative: hashlib.sha256((source_root / relative).read_bytes()).hexdigest()
            for relative in ("build.zig", "build.zig.zon", "src/root.zig", "tests/package_consumer.py",
                             "tests/package_consumer/build.zig", "tests/package_consumer/build.zig.zon",
                             "tests/package_consumer/main.zig", "tests/package_consumer/platform.zig", "tests/package_consumer/tests.zig")
        }
        report = {"status": "passed", "toolchain": f"Zig {version.stdout.strip()}", "optimize": args.optimize,
                  "host": {"system": platform.system(), "machine": platform.machine()},
                  "build_command": command, "binary_sha256": binary_hash,
                  "source_sha256": source_hashes,
                  "single_threaded": args.single_threaded, "modes": results,
                  "platform_qualification": qualification,
                  "fetched_package_hash": package_hash,
                  "fetched_archive_sha256": archive_hash, "distribution_paths": distribution_paths,
                  "scope": "Independent b.dependency/module import and native executable run; Zig APIs only."}
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
