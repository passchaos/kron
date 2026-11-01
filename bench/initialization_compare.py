#!/usr/bin/env python3
"""Compare externally built init candidates with complete verified file trials."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

import regression

sys.path.insert(0, str(Path(__file__).resolve().parent / "cpp_reference"))
import run as workflow


def check_configuration(row, case, events, warmup):
    mode, storage, producers, schema, record_bytes, phase = case
    expected = {"mode": mode, "storage": storage, "producers": producers,
                "prepared_schema": schema, "max_record_bytes": record_bytes,
                "phase": phase, "events": events, "warmup_events": warmup,
                "queue_slots": 256, "consumer_batches_per_queue": 4,
                "backend_requested": "portable", "backend_selected": "portable",
                "file_buffer_bytes": 65536, "event_clock": "std.Io_dynamic_system",
                "metadata": "full", "optimize": "ReleaseFast"}
    for key, value in expected.items():
        if row.get(key) != value:
            raise ValueError(f"changed trial input {key}: {row.get(key)!r} != {value!r}")
    channels = producers + 1 if mode == "spsc" else 1
    stride = (64 + record_bytes + 63) & ~63
    per_queue = 4096 + 256 * stride
    if schema:
        per_queue = (per_queue + 4095) & ~4095
        per_queue += 2 * ((64 + 4096 + 63) & ~63)
    if row["queue_reserved_bytes"] != per_queue * channels:
        raise ValueError("changed queue storage budget")


def comparison(rows, cases, repeats):
    metrics = ("init_ns", "preparation_ns", "producer_wall_ns", "flush_ns",
               "shutdown_ns", "cleanup_ns", "total_ns", "lifecycle_ns",
               "written_records_per_sec", "p50_ns", "p99_ns", "p999_ns")
    output = []
    for case in cases:
        sides = {}
        for side in ("before", "after"):
            selected = [row for row in rows if tuple(row["case"]) == tuple(case) and row["side"] == side]
            if len(selected) != repeats or {row["repetition"] for row in selected} != set(range(repeats)):
                raise ValueError("incomplete comparison group")
            sides[side] = selected
        group = {"case": list(case), "metrics": {}}
        for metric in metrics:
            if any(row[metric] is None for rows_side in sides.values() for row in rows_side):
                continue
            before = regression.summary([row[metric] for row in sides["before"]])
            after = regression.summary([row[metric] for row in sides["after"]])
            stable = all(item["cv"] <= .10 and item["relative_spread"] <= .10 for item in (before, after))
            a, b = before["median_bootstrap_ci95"], after["median_bootstrap_ci95"]
            separate = b[1] < a[0] or a[1] < b[0]
            group["metrics"][metric] = {"before": before, "after": after,
                                       "median_change_percent": (after["median"] / before["median"] - 1) * 100 if before["median"] else None,
                                       "repeatability": "passed" if stable else "inconclusive",
                                       "median_intervals_separate": separate}
        output.append(group)
    return {"scope": "Same full JSON workload and complete written/close lifecycle; no Foundation comparison or durable trial.",
            "repeatability_limit": .10, "groups": output}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True, type=Path)
    parser.add_argument("--after", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--events", type=int, default=100000)
    parser.add_argument("--warmup", type=int, default=1000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--record-budgets", default="512,8192")
    args = parser.parse_args()
    budgets = tuple(map(int, args.record_budgets.split(",")))
    if not 1 <= args.events <= 1000000 or not 0 <= args.warmup <= 100000 or not 5 <= args.repeats <= 9 or not 1 <= args.timeout <= 120 or not budgets or not set(budgets) <= {512, 8192} or len(set(budgets)) != len(budgets):
        parser.error("invalid bounded measurement configuration")
    binaries = {"before": args.before.resolve(strict=True), "after": args.after.resolve(strict=True)}
    digests = {side: workflow.sha256(binary) for side, binary in binaries.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parent.parent
    sources = {str(path.relative_to(root)): workflow.sha256(path) for path in sorted((root / "src").rglob("*.zig"))}
    cpus = workflow.affinity("auto")
    cases = list(itertools.product(("async", "spsc"), ("memory", "mmap"), (1, 4), (False, True), budgets, ("batch", "sampled")))
    manifest = {"before": str(binaries["before"]), "after": str(binaries["after"]),
                "binary_sha256": digests, "capture_source_sha256": sources,
                "harness_sha256": workflow.sha256(root / "bench/cpp_reference/kron_reference.zig"),
                "driver_sha256": workflow.sha256(__file__), "host": platform.uname()._asdict(),
                "starting_load": os.getloadavg(), "affinity": cpus, "events": args.events,
                "warmup": args.warmup, "repeats": args.repeats, "cases": cases}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rows = []
    with (args.output / "results.jsonl").open("x") as evidence:
        for repetition in range(args.repeats):
            for case in (cases if repetition % 2 == 0 else list(reversed(cases))):
                mode, storage, producers, schema, record_bytes, phase = case
                for side in (("before", "after") if repetition % 2 == 0 else ("after", "before")):
                    binary = binaries[side]
                    if workflow.sha256(binary) != digests[side] or any(workflow.sha256(root / name) != digest for name, digest in sources.items()):
                        raise ValueError("source or binary changed during capture")
                    temporary = Path(tempfile.mkdtemp(prefix="kron-init-compare-"))
                    artifact = temporary / "events.jsonl"
                    command = ["taskset", "-c", ",".join(map(str, cpus)), str(binary), f"--output={artifact}",
                               f"--mode={mode}", f"--storage={storage}", f"--producers={producers}",
                               f"--schema={'true' if schema else 'false'}", f"--max-record-bytes={record_bytes}",
                               f"--phase={phase}", f"--events={args.events}", f"--warmup={args.warmup}",
                               "--queue-slots=256", "--consumer-batches=4", "--backend=portable"]
                    try:
                        process = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout)
                        (temporary / "stdout.log").write_text(process.stdout)
                        (temporary / "stderr.log").write_text(process.stderr)
                        process.check_returncode()
                        row = json.loads(process.stdout)
                        check_configuration(row, case, args.events, args.warmup)
                        workflow.verify(row, artifact, args.events, args.warmup)
                    except (Exception, KeyboardInterrupt) as error:
                        (args.output / "failure.json").write_text(json.dumps({"command": command, "error": str(error), "retained_directory": str(temporary), "retry_started": False}, indent=2) + "\n")
                        raise
                    row.update(side=side, repetition=repetition, case=case, command=command,
                               binary_sha256=digests[side], load=os.getloadavg())
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                    shutil.rmtree(temporary)
            print(f"repetition {repetition + 1}/{args.repeats}: {len(rows)} verified complete trials", flush=True)
    (args.output / "comparison.json").write_text(json.dumps(comparison(rows, cases, args.repeats), indent=2) + "\n")
    print(f"verified {len(rows) * (args.events + args.warmup)} physical JSON records across {len(rows)} complete trials")


if __name__ == "__main__":
    main()
