#!/usr/bin/env python3
"""Same executable, real complete JSON files: portable versus Linux io_uring."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

import run as workflow
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import regression


def verify_trial(row, artifact, events, warmup, backend, mode, storage, producers, phase):
    workflow.verify(row, artifact, events, warmup)
    if row["backend_selected"] != backend or row["backend_requested"] != backend or row["consumer_batches_per_queue"] != 4:
        raise ValueError("wrong actual backend or collector budget")
    if row["queue_slots"] != 256 or row["max_record_bytes"] != 512:
        raise ValueError("changed queue or record budget")
    if (row["mode"], row["storage"], row["producers"], row["phase"]) != (mode, storage, producers, phase):
        raise ValueError("unexpected workload")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--events", type=int, default=100000)
    parser.add_argument("--warmup", type=int, default=1000)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()
    if not 1 <= args.events <= 1000000 or not 0 <= args.warmup <= 100000 or not 5 <= args.repeats <= 10 or not 1 <= args.timeout <= 120:
        parser.error("invalid bounded trial budget")
    binary = args.binary.resolve(strict=True)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    affinity = workflow.affinity("auto")
    root = Path(__file__).resolve().parents[2]
    hashes = {str(file.relative_to(root)): workflow.sha256(file) for file in sorted((root / "src").rglob("*.zig"))}
    digest = workflow.sha256(binary)
    manifest = {"configuration": vars(args) | {"binary": str(binary), "output_dir": str(output)},
                "binary_sha256": digest, "production_source_sha256": hashes,
                "harness_sha256": workflow.sha256(Path(__file__).with_name("kron_reference.zig")),
                "driver_sha256": workflow.sha256(__file__), "affinity": affinity,
                "host": platform.uname()._asdict(), "starting_load": os.getloadavg(),
                "scope": "Memory/Mmap shared/SPSC P1/P4 full JSON, system clock, actual file, final written flush and close; no durable flush"}
    # Path objects in argparse's options are serialized explicitly.
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    cases = [(mode, storage, producers, phase)
             for mode in ("async", "spsc") for storage in ("memory", "mmap")
             for producers in (1, 4) for phase in ("batch", "sampled")]
    total = len(cases) * 2 * args.repeats
    rows = []
    with (output / "results.jsonl").open("x") as evidence:
        for repetition in range(args.repeats):
            ordered = cases if repetition % 2 == 0 else list(reversed(cases))
            for mode, storage, producers, phase in ordered:
                for backend in (("portable", "linux_uring") if repetition % 2 == 0 else ("linux_uring", "portable")):
                    if workflow.sha256(binary) != digest or any(workflow.sha256(root / name) != value for name, value in hashes.items()):
                        raise ValueError("source or binary changed during capture")
                    temporary = Path(tempfile.mkdtemp(prefix="kron-file-backend-"))
                    artifact = temporary / "events.jsonl"
                    command = ["taskset", "-c", ",".join(map(str, affinity)), str(binary), f"--backend={backend}",
                               f"--output={artifact}", f"--events={args.events}", f"--warmup={args.warmup}",
                               f"--producers={producers}", f"--phase={phase}", "--queue-slots=256", "--consumer-batches=4",
                               f"--mode={mode}", f"--storage={storage}", "--schema=false"]
                    try:
                        process = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout)
                        (temporary / "stdout.log").write_text(process.stdout)
                        (temporary / "stderr.log").write_text(process.stderr)
                        process.check_returncode()
                        row = json.loads(process.stdout)
                        verify_trial(row, artifact, args.events, args.warmup, backend, mode, storage, producers, phase)
                        row.update(backend=backend, repetition=repetition, command=command, binary_sha256=digest, load=os.getloadavg())
                    except (Exception, KeyboardInterrupt) as error:
                        (output / "failure.json").write_text(json.dumps({"command": command, "error": str(error), "retained_directory": str(temporary), "retry_started": False}, indent=2) + "\n")
                        raise
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                    shutil.rmtree(temporary)
                print(f"{len(rows)}/{total}: {mode}/{storage} P{producers} {phase}, every physical record verified", flush=True)
    groups = []
    for mode, storage, producers, phase in cases:
        selected = [row for row in rows if (row["mode"], row["storage"], row["producers"], row["phase"]) == (mode, storage, producers, phase)]
        metrics = ("written_records_per_sec", "init_ns", "producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns", "lifecycle_ns")
        if phase == "sampled":
            metrics += ("p50_ns", "p99_ns", "p999_ns")
        measured = {}
        for metric in metrics:
            distributions = {backend: regression.summary([row[metric] for row in selected if row["backend"] == backend]) for backend in ("portable", "linux_uring")}
            left, right = [distributions[backend]["median_bootstrap_ci95"] for backend in ("portable", "linux_uring")]
            measured[metric] = distributions | {
                "uring_over_portable": distributions["linux_uring"]["median"] / distributions["portable"]["median"] if distributions["portable"]["median"] else None,
                "qualification": "local_repeatability_within_10_percent" if all(d["cv"] <= .1 and d["relative_spread"] <= .1 for d in distributions.values()) else "inconclusive",
                "bootstrap_intervals_overlap": max(left[0], right[0]) <= min(left[1], right[1])}
        groups.append({"mode": mode, "storage": storage, "producers": producers, "phase": phase, "metrics": measured})
    assert len(rows) == total
    report = {"trials": total, "physical_records_verified": sum(row["file_records_verified"] for row in rows), "groups": groups,
              "binary_sha256": digest, "noise_limit": .1, "ending_load": os.getloadavg(), "scope": manifest["scope"]}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    for group in groups:
        if group["phase"] == "batch":
            metric = group["metrics"]["written_records_per_sec"]
            print(group["mode"], group["storage"], group["producers"], "portable", round(metric["portable"]["median"]),
                  "io_uring", round(metric["linux_uring"]["median"]), metric["qualification"], flush=True)


if __name__ == "__main__":
    main()
