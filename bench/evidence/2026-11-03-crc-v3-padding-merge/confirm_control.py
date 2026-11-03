#!/usr/bin/env python3
"""Targeted reproduction check for the six qualified E-core negatives."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "bench/cpp_reference"))
import run as workflow
from qualification import paired_metric

BINARIES = {"before": ROOT / ".zig-cache/crc-v3-padding-merge/before-reference",
            "after": ROOT / ".zig-cache/crc-v3-padding-merge/candidate-reference"}
CPUS = [16, 18, 20, 22, 24, 26]
CASES = [
    ("async", "mmap", 1, "batch", False, "written_records_per_sec"),
    ("async", "mmap", 1, "batch", False, "written_flush_records_per_sec"),
]


def main():
    rows = []
    for mode, storage, producers, phase, schema, metric in CASES:
        selected = {label: [] for label in BINARIES}
        for repetition in range(5):
            order = ("before", "after") if repetition % 2 == 0 else ("after", "before")
            for label in order:
                temporary = Path(tempfile.mkdtemp(prefix="kron-confirm-"))
                artifact = temporary / "events.jsonl"
                command = ["taskset", "-c", ",".join(map(str, CPUS)), str(BINARIES[label]),
                           "--frontend=managed", "--backend=portable", f"--output={artifact}",
                           "--events=100000", "--warmup=1000", f"--producers={producers}",
                           f"--phase={phase}", "--queue-slots=256", f"--mode={mode}",
                           f"--storage={storage}", f"--schema={str(schema).lower()}"]
                process = subprocess.run(command, capture_output=True, text=True, check=True, timeout=120)
                row = json.loads(process.stdout)
                workflow.verify(row, artifact, 100000, 1000)
                row.update(label=label, repetition=repetition)
                row["written_flush_records_per_sec"] = 100000 * 1e9 / (row["producer_wall_ns"] + row["flush_ns"])
                selected[label].append(row)
                shutil.rmtree(temporary)
        result = paired_metric(selected["after"], selected["before"], metric, metric not in ("init_ns", "p50_ns", "p99_ns"))
        rows.append({"mode": mode, "storage": storage, "producers": producers, "phase": phase,
                     "schema": schema, "metric": metric, "qualification": result})
        print(mode, storage, producers, phase, schema, metric, result["assessment"], result["paired_speed_ratio"], flush=True)
    (HERE / "control-confirmation.json").write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main()
