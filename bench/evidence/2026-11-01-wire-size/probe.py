#!/usr/bin/env python3
"""Compare all public encoding benchmark cases, retaining exact output data."""
import json
import os
import statistics
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASES = ("flat5typednumbers", "nested_depth2_array_group", "max256nodes")
OPERATIONS = ("size_only", "value_size_only", "encode", "binary_archive", "reference_size_only", "reference_encode")


def validate(data):
    expected = {(case, op, rep) for case in CASES for op in OPERATIONS for rep in range(5)}
    rows = {}
    for line in data.splitlines():
        row = json.loads(line)
        key = (row["case"], row["operation"], row["repetition"])
        if key not in expected or key in rows or row["iterations"] != 10000 or row["elapsed_ns"] <= 0:
            raise ValueError("invalid or duplicate probe row")
        rows[key] = row
    if rows.keys() != expected:
        raise ValueError("missing probe cases")
    return rows


def main():
    destination = HERE / "probe"
    destination.mkdir(exist_ok=False)
    os.sched_setaffinity(0, {0})
    counts = {label: [] for label in ("before", "after")}
    times = {}
    for pair in range(5):
        rows = {}
        for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            stem = f"{pair}-{label}"
            command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "-x,", "-o", str(destination / f"{stem}.csv"),
                       str(HERE / f"kron-ref-probe-{label}"), "--iterations=10000", "--repetitions=5"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (destination / f"{stem}.log").write_text(result.stdout + result.stderr)
            result.check_returncode()
            rows[label] = validate(result.stdout)
            counters = {}
            for line in (destination / f"{stem}.csv").read_text().splitlines():
                fields = line.split(",")
                if len(fields) < 3 or not fields[0].isdigit():
                    continue
                for metric in ("instructions", "cycles"):
                    if metric in fields[2]:
                        counters[metric] = int(fields[0])
            if counters.keys() != {"instructions", "cycles"}:
                raise ValueError("missing hardware events")
            counts[label].append(counters)
            for key, row in rows[label].items():
                times.setdefault(key[:2], {"before": [], "after": []})[label].append(row["ns_per_call"])
        for key, before in rows["before"].items():
            after = rows["after"][key]
            if before.keys() != after.keys():
                raise ValueError("changed report schema")
            for name, value in before.items():
                if name not in ("elapsed_ns", "ns_per_call") and value != after[name]:
                    raise ValueError(f"changed inputs/output: {key} {name}")
        print(f"pair {pair + 1}/5: all 90 shapes, checksums and sizes agree", flush=True)
    def compare(values):
        result = {}
        for label, items in values.items():
            median = statistics.median(items)
            result[label] = {"median": median, "min": min(items), "max": max(items), "spread": (max(items) - min(items)) / median}
        result["change_percent"] = (result["after"]["median"] / result["before"]["median"] - 1) * 100
        result["qualification"] = "within_noise_budget" if all(result[label]["spread"] <= 0.1 for label in values) else "inconclusive"
        return result
    report = {"cpu": 0, "pairs": 5, "scope": "size, encode and binary archive with public validation, fixture mutation and encoded-byte Wyhash; not async/file throughput",
              "counters": {metric: compare({label: [row[metric] for row in items] for label, items in counts.items()}) for metric in ("instructions", "cycles")},
              "cases": [{"case": case, "operation": op, **compare(values)} for (case, op), values in times.items()]}
    (destination / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
