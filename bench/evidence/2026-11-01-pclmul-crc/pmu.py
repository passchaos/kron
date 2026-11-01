#!/usr/bin/env python3
"""Fixed-affinity whole-process PMU comparison for PCLMUL CRC block loop."""
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
AFFINITY = [0, 2, 4, 6, 8, 10]
REPETITIONS = 5
CASES = [
    ("spsc", "memory", 4, "batch"),
    ("async", "memory", 1, "batch"),
]
BINARIES = {
    "before": HERE / "kron-ref-before-pclmul",
    "after": HERE / "kron-ref-after-pclmul",
}
METRICS = ("task-clock", "cycles", "instructions")


def load_average():
    try:
        return os.getloadavg()
    except OSError:
        return None


def parse_perf(text):
    values = {}
    for line in text.splitlines():
        parts = line.split(",")
        if len(parts) < 3:
            continue
        raw, _, event = parts[0], parts[1], parts[2]
        if event.startswith("cpu_core/"):
            event = event[len("cpu_core/"):-1]
        if event not in METRICS:
            continue
        # task-clock reports elapsed milliseconds in field 0 and the raw
        # nanosecond count in field 3; hardware counters report the count first.
        raw = parts[3].strip() if event == "task-clock" else parts[0].strip()
        if not raw.isdigit():
            continue
        values[event] = int(raw)
    assert set(values) == set(METRICS), values
    return values


def main():
    report = HERE / "pmu-results.jsonl"
    assert not report.exists(), "Do not restart or overwrite an existing capture"
    work = Path(tempfile.mkdtemp(prefix="kron-pclmul-pmu-"))
    rows = []
    with report.open("x") as output:
        for repetition in range(REPETITIONS):
            for mode, storage, producers, phase in CASES:
                labels = ("before", "after") if repetition % 2 == 0 else ("after", "before")
                for label in labels:
                    artifact = work / f"{repetition}-{mode}-{storage}-{producers}-{phase}-{label}.jsonl"
                    workflow = work / f"{repetition}-{mode}-{storage}-{producers}-{phase}-{label}.json"
                    command = [
                        "perf", "stat", "-e", "task-clock,cycles,instructions", "-x,",
                        "taskset", "-c", ",".join(map(str, AFFINITY)), str(BINARIES[label]),
                        f"--output={artifact}", "--events=100000", "--warmup=1000",
                        f"--producers={producers}", f"--phase={phase}", "--queue-slots=256",
                        f"--mode={mode}", f"--storage={storage}",
                    ]
                    with workflow.open("x") as stdout:
                        process = subprocess.run(command, cwd=ROOT, stdout=stdout, stderr=subprocess.PIPE, text=True, timeout=120)
                    if process.returncode:
                        (work / "perf-stderr.log").write_text(process.stderr)
                        raise RuntimeError(f"pmu failed; stderr retained at {work}")
                    row = json.loads(workflow.read_text())
                    assert row["status"] == "ok" and row["optimize"] == "ReleaseFast"
                    assert row["accepted"] == row["written"] == 100000 and row["final_pending"] == 0
                    counters = parse_perf(process.stderr)
                    row.update(label=label, repetition=repetition, mode=mode, storage=storage,
                               producers=producers, phase=phase, counters=counters,
                               command=command, load_average=load_average())
                    output.write(json.dumps(row) + "\n")
                    output.flush()
                    rows.append(row)
                    print(f"pmu {repetition} {mode} {storage} P{producers} {phase} {label}: "
                          f"instructions={counters['instructions']} cycles={counters['cycles']}", flush=True)
    summary = {}
    for mode, storage, producers, phase in CASES:
        selected = [row for row in rows if (row["mode"], row["storage"], row["producers"], row["phase"]) == (mode, storage, producers, phase)]
        entry = {}
        for metric in (*METRICS, "written_records_per_sec"):
            values = {}
            for label in ("before", "after"):
                if metric == "written_records_per_sec":
                    items = [row[metric] for row in selected if row["label"] == label]
                else:
                    items = [row["counters"][metric] for row in selected if row["label"] == label]
                values[label] = {
                    "median": statistics.median(items),
                    "min": min(items),
                    "max": max(items),
                    "relative_spread": (max(items) - min(items)) / statistics.median(items) if statistics.median(items) else None,
                }
            entry[metric] = {
                **values,
                "after_over_before": values["after"]["median"] / values["before"]["median"]
                    if values["before"]["median"] else None,
                "status": "stable_local_measurement"
                    if all(value["relative_spread"] < 0.10 for value in values.values())
                    else "inconclusive",
            }
        summary[f"{mode}-{storage}-P{producers}-{phase}"] = entry
    result = {
        "trials": len(rows), "pairs": REPETITIONS, "affinity": AFFINITY,
        "noise_limit": 0.10, "load_average": load_average(),
        "scope": "Whole-process user/core PMU counters; includes producer, background formatting/file output, "
                 "written flush, shutdown and cleanup. User counters exclude kernel I/O work.",
        "summary": summary,
    }
    (HERE / "pmu-summary.json").write_text(json.dumps(result, indent=2) + "\n")
    shutil.rmtree(work)


if __name__ == "__main__":
    main()
