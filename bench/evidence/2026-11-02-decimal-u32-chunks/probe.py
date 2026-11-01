#!/usr/bin/env python3
"""Paired primitive PMU; full buffers verified against std inside each process."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    binaries = {label: ROOT / f".zig-cache/decimal-u32-chunks/probe-{label}" for label in ("before", "after")}
    identities = {label: sha(path) for label, path in binaries.items()}
    spec = importlib.util.spec_from_file_location("regression", ROOT / "bench/regression.py")
    regression = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(regression)
    logs = HERE / "primitive-trials"
    logs.mkdir(exist_ok=True)
    destination = HERE / "primitive-results.jsonl"
    assert not destination.exists(), "Never overwrite prior captures"
    rows = []
    with destination.open("x") as output:
        for pair in range(5):
            for case in ("small", "record", "full", "signed", "wide"):
                paired = []
                for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                    assert all(sha(path) == identities[key] for key, path in binaries.items())
                    name = f"{pair}-{case}-{label}"
                    command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "-x,", "-o", str(logs / f"{name}.csv"), "--",
                               "taskset", "-c", "0", str(binaries[label]), case, "1000"]
                    run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    (logs / f"{name}.log").write_text(run.stdout + run.stderr)
                    assert run.returncode == 0, name
                    row = json.loads(run.stdout)
                    assert row["output_verified"] is True and row["optimize"] == "ReleaseFast"
                    assert row["case"] == case and row["values"] == 4096 and row["repetitions"] == 1000
                    counters = {}
                    for line in (logs / f"{name}.csv").read_text().splitlines():
                        parts = line.split(",")
                        if len(parts) < 3 or not parts[0].isdigit(): continue
                        for metric in ("instructions", "cycles"):
                            if metric in parts[2]: counters[metric] = int(parts[0])
                    assert counters.keys() == {"instructions", "cycles"}
                    row.update(counters, label=label, pair=pair, command=command, binary_sha256=identities[label])
                    paired.append(row)
                    rows.append(row)
                    output.write(json.dumps(row) + "\n")
                    output.flush()
                assert paired[0]["checksum"] == paired[1]["checksum"] and paired[0]["bytes_per_batch"] == paired[1]["bytes_per_batch"]
                print(case, pair, "all output bytes match", flush=True)
    cases = []
    for case in ("small", "record", "full", "signed", "wide"):
        metrics = {}
        for metric in ("instructions", "cycles", "ns_per_value"):
            values = {label: regression.summary([row[metric] for row in rows if row["case"] == case and row["label"] == label]) for label in binaries}
            left, right = (values[label]["median_bootstrap_ci95"] for label in binaries)
            metrics[metric] = {**values, "after_over_before": values["after"]["median"] / values["before"]["median"],
                              "bootstrap_intervals_overlap": max(left[0], right[0]) <= min(left[1], right[1]),
                              "stable": all(value["cv"] < .1 and value["relative_spread"] < .1 for value in values.values())}
        cases.append(dict(case=case, metrics=metrics))
    report = {"trials": len(rows), "binary_sha256": identities, "cases": cases,
              "scope": "Primitive fixed writer; output verified against std and complete buffers consumed each batch. User PMU also includes preparation/oracle/startup. No per-value clock/hash in timed loops. Not full logging or cross-library performance."}
    (HERE / "primitive-comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    for case in cases: print(case["case"], {metric: value["after_over_before"] for metric, value in case["metrics"].items()})


if __name__ == "__main__":
    main()
