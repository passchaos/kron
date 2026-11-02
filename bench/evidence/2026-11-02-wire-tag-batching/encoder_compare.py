#!/usr/bin/env python3
"""Check ordinary public encoder overhead separately from fused wire delivery."""
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
    binaries = {label: ROOT / f".zig-cache/wire-tag-encoder-{label}" for label in ("before", "after")}
    identities = {label: sha(path) for label, path in binaries.items()}
    spec = importlib.util.spec_from_file_location("regression", ROOT / "bench/regression.py")
    regression = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(regression)
    logs = HERE / "encoder-trials"
    logs.mkdir(exist_ok=True)
    destination = HERE / "encoder-results.jsonl"
    assert not destination.exists()
    rows = []
    with destination.open("x") as output:
        for pair in range(5):
            for format in ("json", "text", "logfmt"):
                paired = []
                for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                    assert all(sha(path) == identities[key] for key, path in binaries.items())
                    name = f"{pair}-{format}-{label}"
                    command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u", "-x,", "-o", str(logs / f"{name}.csv"), "--",
                               "taskset", "-c", "0", str(binaries[label]), format]
                    run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    (logs / f"{name}.log").write_text(run.stdout + run.stderr)
                    assert run.returncode == 0
                    cases = [json.loads(line) for line in run.stdout.splitlines()]
                    assert [row["case"] for row in cases] == ["scalar5", "nested20", "wide5"]
                    assert all(row["iterations"] == 300000 for row in cases)
                    counters = {}
                    for line in (logs / f"{name}.csv").read_text().splitlines():
                        parts = line.split(",")
                        if len(parts) < 3 or not parts[0].isdigit(): continue
                        for metric in ("instructions", "cycles"):
                            if metric in parts[2]: counters[metric] = int(parts[0])
                    assert counters.keys() == {"instructions", "cycles"}
                    record = dict(label=label, pair=pair, format=format, command=command, binary_sha256=identities[label], cases=cases, **counters)
                    rows.append(record); paired.append(record)
                    output.write(json.dumps(record) + "\n"); output.flush()
                for before, after in zip(paired[0]["cases"], paired[1]["cases"]):
                    assert before["checksum"] == after["checksum"] and before["output_bytes"] == after["output_bytes"]
                print(format, pair, "three complete-output checksums agree", flush=True)
    assessments = []
    for format in ("json", "text", "logfmt"):
        metrics = {}
        selected = [row for row in rows if row["format"] == format]
        for key in ("instructions", "cycles", "scalar5", "nested20", "wide5"):
            def value(row):
                return row[key] if key in ("instructions", "cycles") else next(case["ns_per_record"] for case in row["cases"] if case["case"] == key)
            summaries = {label: regression.summary([value(row) for row in selected if row["label"] == label]) for label in binaries}
            left, right = (summaries[label]["median_bootstrap_ci95"] for label in binaries)
            metrics[key] = {**summaries, "after_over_before": summaries["after"]["median"] / summaries["before"]["median"],
                            "overlap": max(left[0], right[0]) <= min(left[1], right[1]), "stable": all(s["cv"] < .1 and s["relative_spread"] < .1 for s in summaries.values())}
        assessments.append(dict(format=format, metrics=metrics))
    (HERE / "encoder-comparison.json").write_text(json.dumps({"trials": len(rows), "binary_sha256": identities, "assessments": assessments,
        "scope": "Ordinary public encoder; includes changing values/full-output Wyhash. PMU includes process setup. No file workflow or fused path."}, indent=2) + "\n")


if __name__ == "__main__":
    main()
