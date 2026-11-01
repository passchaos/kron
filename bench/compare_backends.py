#!/usr/bin/env python3
"""Run identical bounded file workloads, alternating portable/io_uring order."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import statistics
import subprocess
import time


def optional_text(path):
    try:
        return pathlib.Path(path).read_text().strip()
    except OSError:
        return None


def command_metadata(command):
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=5)
        if completed.returncode == 0:
            return json.loads(completed.stdout)
        return {"available": False, "error": completed.stderr.strip()}
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        return {"available": False, "error": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--events", type=int, default=10000)
    parser.add_argument("--producers", type=int, choices=(1, 4, 16), default=4)
    parser.add_argument("--mode", choices=("sync", "async", "spsc"), default="async")
    parser.add_argument("--fields", type=int, choices=(0, 5, 10), default=5)
    parser.add_argument("--payload", choices=("numeric", "short", "long"), default="numeric")
    parser.add_argument("--timeout-seconds", type=int, default=60)
    arguments = parser.parse_args()
    if not 1 <= arguments.repeats <= 20 or not 1 <= arguments.events <= 10000000:
        parser.error("repeats must be 1..20 and events must be 1..10000000")
    binary = pathlib.Path(arguments.binary).resolve()
    output_dir = pathlib.Path(arguments.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    base = [str(binary), f"--mode={arguments.mode}", "--sink=file", f"--events={arguments.events}",
            f"--producers={arguments.producers}", f"--fields={arguments.fields}", f"--payload={arguments.payload}",
            "--format=json", "--temperature=warm", "--warmup-events=1000", "--samples=10000",
            "--buffer-bytes=65536", "--queue-depth=4", "--journal-slots=256", "--channel-slots=256",
            "--max-record-bytes=16384", "--journal-bytes=268435456", "--overflow=block",
            f"--work-dir={output_dir / 'artifacts'}"]
    metadata = {
        "captured_unix_seconds": time.time(), "uname": dict(platform.uname()._asdict()),
        "cpu_count": os.cpu_count(), "affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
        "cpuinfo": optional_text("/proc/cpuinfo"),
        "cpu0_governor": optional_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "base_command": base,
        "repeats": arguments.repeats,
        "filesystem": command_metadata(["findmnt", "-T", str(output_dir), "-o", "SOURCE,FSTYPE,OPTIONS", "--json"]),
        "cpu_topology": command_metadata(["lscpu", "--json"]),
        "block_devices": command_metadata(["lsblk", "-o", "NAME,MODEL,ROTA,SIZE", "--json"]),
    }
    try:
        revision = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, timeout=5)
        metadata["git_revision"] = revision.stdout.strip() if revision.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        metadata["git_revision"] = None
    (output_dir / "machine.json").write_text(json.dumps(metadata, indent=2) + "\n")
    rows = []
    with (output_dir / "results.jsonl").open("w") as evidence:
        for repetition in range(arguments.repeats):
            order = ("portable", "linux_uring") if repetition % 2 == 0 else ("linux_uring", "portable")
            for backend in order:
                command = [*base, f"--backend={backend}"]
                completed = subprocess.run(command, capture_output=True, text=True, timeout=arguments.timeout_seconds)
                current = [json.loads(line) for line in completed.stdout.splitlines()]
                if len(current) != 2:
                    raise RuntimeError((command, completed.returncode, completed.stdout, completed.stderr))
                for row in current:
                    row["repetition"] = repetition
                    row["command"] = command
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                if all(row["status"] == "unsupported" for row in current) and backend == "linux_uring":
                    print(f"io_uring unavailable: {current[0]['error_name']}", flush=True)
                    continue
                if completed.returncode != 0:
                    raise RuntimeError((command, completed.returncode, current, completed.stderr))
                for row in current:
                    if not row["accepted"] == row["sink_written_records"] == arguments.events or row["final_pending"] != 0 or row["backend_selected"] != backend:
                        raise RuntimeError(row)
                print(f"repetition {repetition + 1}: {backend} completed and verified", flush=True)
    summary = {}
    for backend in ("portable", "linux_uring"):
        for phase in ("sampled", "batch"):
            selected = [row for row in rows if row["status"] == "ok" and row["backend_selected"] == backend and row["phase"] == phase]
            if not selected:
                continue
            rates = [row["written_records_per_sec"] for row in selected]
            summary[f"{backend}/{phase}"] = {
                "trials": len(selected), "written_records_per_sec_median": statistics.median(rates),
                "written_records_per_sec_min": min(rates), "written_records_per_sec_max": max(rates),
                "p50_ns_median": statistics.median(row["producer_p50_ns"] for row in selected) if phase == "sampled" else None,
                "p99_ns_median": statistics.median(row["producer_p99_ns"] for row in selected) if phase == "sampled" else None,
                "p999_ns_median": statistics.median(row["producer_p999_ns"] for row in selected) if phase == "sampled" else None,
            }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
