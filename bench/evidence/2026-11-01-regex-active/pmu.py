#!/usr/bin/env python3
"""Whole-process regex probe counters, including compile/init/output work."""
import json
import os
import statistics
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from regex_compare import compare, validate


def main():
    destination = HERE / "pmu"
    destination.mkdir(exist_ok=False)
    cpu = int((HERE / "baseline-cpu.txt").read_text())
    os.sched_setaffinity(0, {cpu})
    samples = {label: [] for label in ("before", "after")}
    for pair in range(5):
        outputs = {}
        for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            binary = HERE / ("kron-ref-before" if label == "before" else "kron-ref-context")
            counters_file = destination / f"{pair}-{label}.csv"
            command = ["perf", "stat", "-e", "instructions:u,cycles:u", "-x,", "-o", str(counters_file),
                       str(binary), "--iterations=10000", "--repetitions=5"]
            process = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (destination / f"{pair}-{label}.log").write_text(process.stdout + process.stderr)
            process.check_returncode()
            outputs[label] = validate([json.loads(line) for line in process.stdout.splitlines()], 5)
            counters = {}
            for line in counters_file.read_text().splitlines():
                fields = line.split(",")
                if len(fields) < 3:
                    continue
                # Hybrid CPUs emit an uncounted atom-PMU row even when the
                # process is pinned to a core CPU. Require real counters below.
                if not fields[0].isdigit():
                    continue
                event = fields[2]
                if "instructions" in event:
                    key = "instructions"
                elif "cycles" in event:
                    key = "cycles"
                else:
                    continue
                if key in counters:
                    raise ValueError("more than one PMU counted the pinned process")
                counters[key] = int(fields[0])
            if counters.keys() != {"instructions", "cycles"}:
                raise ValueError("missing PMU hardware counters")
            samples[label].append(counters)
        compare(outputs["before"], outputs["after"])
        print(f"PMU pair {pair + 1}/5: identical workload/output counts and hashes", flush=True)
    metrics = {}
    for metric in ("instructions", "cycles"):
        entry = {}
        for label in ("before", "after"):
            values = [sample[metric] for sample in samples[label]]
            median = statistics.median(values)
            entry[label] = {"median": median, "min": min(values), "max": max(values),
                            "relative_spread": (max(values) - min(values)) / median}
        entry["change_percent"] = (entry["after"]["median"] / entry["before"]["median"] - 1) * 100
        entry["status"] = "within_noise_budget" if all(entry[label]["relative_spread"] <= 0.1 for label in samples) else "inconclusive"
        metrics[metric] = entry
    report = {"cpu": cpu, "pairs": 5, "load": os.getloadavg(), "metrics": metrics,
              "binary_manifest": "../context-comparison/manifest.json",
              "scope": "whole benchmark process: eight Pattern/Predicate workloads, two sync JSON counters, compile/init, JSON reports; user PMU excludes kernel; no async or file throughput"}
    (destination / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
