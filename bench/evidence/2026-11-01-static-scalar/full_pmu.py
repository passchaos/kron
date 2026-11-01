#!/usr/bin/env python3
"""Whole-file process counters with independent verification of every record."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
AFFINITY = [0, 2, 4, 6, 8, 10]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--after", default=str(HERE / "kron-ref-after"))
    parser.add_argument("--source-root", default=str(ROOT))
    parser.add_argument("--output", default=str(HERE / "full-pmu"))
    args = parser.parse_args()
    source_root = Path(args.source_root).resolve()
    spec = importlib.util.spec_from_file_location("workflow", ROOT / "bench/cpp_reference/run.py")
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    destination = Path(args.output).resolve()
    destination.mkdir(exist_ok=False)
    binaries = {"before": ROOT / "bench/evidence/2026-11-01-wire-size/kron-ref-before", "after": Path(args.after).resolve()}
    source = {str(file.relative_to(source_root)): hashlib.sha256(file.read_bytes()).hexdigest() for file in sorted((source_root / "src").rglob("*.zig"))}
    identities = {label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in binaries.items()}
    rows = []
    for pair in range(5):
        for mode, producers in (("spsc", 4), ("async", 1)):
            for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                if any(hashlib.sha256((source_root / name).read_bytes()).hexdigest() != digest for name, digest in source.items()):
                    raise ValueError("candidate source changed during PMU capture")
                stem = f"{pair}-{mode}-{label}"
                with tempfile.TemporaryDirectory(prefix="kron-static-scalar-pmu-") as temporary:
                    artifact = Path(temporary) / "events.jsonl"
                    command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "-x,", "-o", str(destination / f"{stem}.csv"),
                               "taskset", "-c", ",".join(map(str, AFFINITY)), str(binaries[label]), f"--output={artifact}",
                               "--events=300000", "--warmup=1000", f"--producers={producers}", "--phase=batch", "--queue-slots=256",
                               f"--mode={mode}", "--storage=memory", "--schema=false"]
                    process = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    (destination / f"{stem}.log").write_text(process.stdout + process.stderr)
                    process.check_returncode()
                    row = json.loads(process.stdout)
                    oracle.verify(row, artifact, 300000, 1000)
                    counters = {}
                    for line in (destination / f"{stem}.csv").read_text().splitlines():
                        parts = line.split(",")
                        if len(parts) < 3 or not parts[0].isdigit():
                            continue
                        for metric in ("instructions", "cycles"):
                            if metric in parts[2]:
                                counters[metric] = int(parts[0])
                    if counters.keys() != {"instructions", "cycles"}:
                        raise ValueError("missing counted hardware events")
                    row.update(label=label, pair=pair, counters=counters, binary_sha256=identities[label])
                    rows.append(row)
            print(f"PMU pair {pair + 1}/5 {mode} P{producers}: all physical records verified", flush=True)
    summary = {}
    for mode in ("spsc", "async"):
        summary[mode] = {}
        for metric in ("instructions", "cycles", "written_records_per_sec"):
            entry = {}
            for label in binaries:
                values = [row[metric] if metric == "written_records_per_sec" else row["counters"][metric]
                          for row in rows if row["mode"] == mode and row["label"] == label]
                median = statistics.median(values)
                entry[label] = {"median": median, "min": min(values), "max": max(values), "spread": (max(values) - min(values)) / median}
            entry["change_percent"] = (entry["after"]["median"] / entry["before"]["median"] - 1) * 100
            entry["qualification"] = "within_noise_budget" if all(entry[label]["spread"] <= 0.1 for label in binaries) else "inconclusive"
            summary[mode][metric] = entry
    (destination / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    report = {"trials": len(rows), "physical_records_verified": sum(row["file_records_verified"] for row in rows),
              "affinity": AFFINITY, "summary": summary, "binary_sha256": identities, "source_root": str(source_root), "source_sha256": source,
              "scope": "whole user process producer, JSON/file consumer, final written flush, shutdown and cleanup; user PMU excludes kernel work; no durable flush"}
    (destination / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
