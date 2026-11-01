#!/usr/bin/env python3
"""Five paired whole encoder probe PMU trials with exact output hashes."""
import json
import os
from pathlib import Path
import statistics
import subprocess

HERE = Path(__file__).resolve().parent


def main():
    destination = HERE / os.environ.get("KRON_DECIMAL_PROBE_OUTPUT", "probe")
    destination.mkdir(exist_ok=False)
    os.sched_setaffinity(0, {0})
    counters = {label: [] for label in ("before", "after")}
    times = {}
    for pair in range(5):
        rows = {}
        for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "-x,", "-o", str(destination / f"{pair}-{label}.csv"),
                       str(HERE / f"kron-ref-probe-{label}")]
            process = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (destination / f"{pair}-{label}.log").write_text(process.stdout + process.stderr)
            process.check_returncode()
            records = [json.loads(line) for line in process.stdout.splitlines()]
            if [row["case"] for row in records] != ["scalar5", "nested20", "wide5"]:
                raise ValueError("missing or changed probe cases")
            rows[label] = records
            values = {}
            for line in (destination / f"{pair}-{label}.csv").read_text().splitlines():
                fields = line.split(",")
                if len(fields) < 3 or not fields[0].isdigit():
                    continue
                for metric in ("instructions", "cycles"):
                    if metric in fields[2]:
                        values[metric] = int(fields[0])
            if values.keys() != {"instructions", "cycles"}:
                raise ValueError("missing hardware counters")
            counters[label].append(values)
            for row in records:
                if row["iterations"] != 300000 or row["output_bytes"] <= 0 or row["elapsed_ns"] <= 0:
                    raise ValueError("invalid workload accounting")
                times.setdefault(row["case"], {"before": [], "after": []})[label].append(row["ns_per_record"])
        for old, new in zip(rows["before"], rows["after"]):
            for key in ("case", "iterations", "checksum", "output_bytes"):
                if old[key] != new[key]:
                    raise ValueError("probe output changed")
        print(f"probe pair {pair + 1}/5: all output bytes/hashes agree", flush=True)
    def compare(values):
        result = {}
        for label, items in values.items():
            median = statistics.median(items)
            result[label] = {"median": median, "min": min(items), "max": max(items), "spread": (max(items) - min(items)) / median}
        result["change_percent"] = (result["after"]["median"] / result["before"]["median"] - 1) * 100
        result["qualification"] = "within_noise_budget" if all(result[label]["spread"] <= 0.1 for label in values) else "inconclusive"
        return result
    report = {"cpu": 0, "pairs": 5, "scope": "whole encoder probe includes input mutation, full JSON hash, reports and initialization; no file or async throughput",
              "counters": {metric: compare({label: [row[metric] for row in items] for label, items in counters.items()}) for metric in ("instructions", "cycles")},
              "case_ns": {case: compare(values) for case, values in times.items()}}
    (destination / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
