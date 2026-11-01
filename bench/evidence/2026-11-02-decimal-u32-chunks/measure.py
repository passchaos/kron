#!/usr/bin/env python3
"""Frozen managed/shared complete JSON before/after, with optional user PMU."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
AFFINITY = [0, 2, 4, 6, 8, 10]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pmu", action="store_true")
    parser.add_argument("--p1-sampled", action="store_true", help="Recheck only shared P1 sampled Memory/Mmap")
    parser.add_argument("--capture-name")
    args = parser.parse_args()
    provenance = {label: json.loads((HERE / f"{label}-provenance.json").read_text()) for label in ("before", "after")}
    binaries = {label: ROOT / record["binary_path"] for label, record in provenance.items()}
    identities = {label: record["binary_sha256"] for label, record in provenance.items()}
    oracle = module("reference_oracle", ROOT / "bench/cpp_reference/run.py")
    regression = module("paired_summary", ROOT / "bench/regression.py")
    cases = [(storage, producers) for storage in ("memory", "mmap") for producers in (1, 4)]
    phases = ["batch"] if args.pmu else ["batch", "sampled"]
    if args.p1_sampled:
        assert not args.pmu
        cases = [(storage, 1) for storage in ("memory", "mmap")]
        phases = ["sampled"]
    events, warmup = 300000, 1000
    stem = args.capture_name or ("pmu" if args.pmu else "workflow")
    assert stem.replace("-", "").replace("_", "").isalnum()

    def guard():
        assert all(sha(ROOT / key) == value for key, value in provenance["after"]["source_sha256"].items())
        assert all(sha(path) == identities[label] for label, path in binaries.items())

    logs = HERE / "trials" / stem
    logs.mkdir(parents=True, exist_ok=True)
    destination = HERE / f"{stem}-results.jsonl"
    assert not destination.exists(), "Preserve prior captures"
    assert set(AFFINITY).issubset(os.sched_getaffinity(0))
    work = Path(tempfile.mkdtemp(prefix=f"kron-filter-cache-{stem}-"))
    rows = []
    with destination.open("x") as output:
        for pair in range(5):
            for storage, producers in cases:
                for phase in phases:
                    for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                        guard()
                        name = f"{pair}-{storage}-P{producers}-{phase}-{label}"
                        directory = work / name
                        directory.mkdir()
                        artifact = directory / "output.jsonl"
                        command = ["taskset", "-c", ",".join(map(str, AFFINITY)), str(binaries[label]),
                                   f"--output={artifact}", "--frontend=managed", f"--events={events}",
                                   f"--warmup={warmup}", f"--producers={producers}", f"--phase={phase}",
                                   "--queue-slots=256", "--mode=async", f"--storage={storage}",
                                   "--schema=false", "--backend=portable"]
                        if args.pmu:
                            command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u",
                                       "-x,", "-o", str(logs / f"{name}.csv"), "--"] + command
                        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                        (logs / f"{name}.log").write_text(process.stdout + process.stderr)
                        if process.returncode:
                            raise RuntimeError(f"failed workload retained at {directory}")
                        row = json.loads(process.stdout)
                        assert row["frontend"] == "managed" and row["optimize"] == "ReleaseFast"
                        assert row["backend_requested"] == row["backend_selected"] == "portable"
                        assert row["mode"] == "async" and row["storage"] == storage and not row["prepared_schema"]
                        assert row["metadata"] == "full" and row["event_clock"] == "std.Io_dynamic_system"
                        assert row["queue_slots"] == 256 and row["max_record_bytes"] == 512
                        assert row["file_buffer_bytes"] == 65536 and row["consumer_batches_per_queue"] == 4
                        oracle.verify(row, artifact, events, warmup)
                        if args.pmu:
                            counters = {}
                            for line in (logs / f"{name}.csv").read_text().splitlines():
                                parts = line.split(",")
                                if len(parts) < 3 or not parts[0].isdigit():
                                    continue
                                for metric in ("instructions", "cycles"):
                                    if metric in parts[2]: counters[metric] = int(parts[0])
                            assert counters.keys() == {"instructions", "cycles"}
                            row.update(counters)
                        guard()
                        row.update(label=label, pair=pair, command=command, binary_sha256=identities[label], load_average=list(os.getloadavg()))
                        rows.append(row)
                        output.write(json.dumps(row) + "\n")
                        output.flush()
                        shutil.rmtree(directory)
                    print(f"{stem} pair {pair} {storage} P{producers} {phase}: {len(rows)} trials verified", flush=True)
    work.rmdir()
    assessments = []
    for storage, producers in cases:
        for phase in phases:
            selected = [r for r in rows if (r["storage"], r["producers"], r["phase"]) == (storage, producers, phase)]
            metrics = ["written_records_per_sec", "producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns", "init_ns", "preparation_ns", "total_ns", "lifecycle_ns", "lifecycle_records_per_sec"]
            if phase == "sampled": metrics += ["p50_ns", "p99_ns", "p999_ns"]
            if args.pmu: metrics += ["instructions", "cycles"]
            assessed = {}
            for metric in metrics:
                values = {label: regression.summary([r[metric] for r in selected if r["label"] == label]) for label in binaries}
                left, right = (values[label]["median_bootstrap_ci95"] for label in binaries)
                assessed[metric] = {**values, "after_over_before": values["after"]["median"] / values["before"]["median"] if values["before"]["median"] else None,
                    "status": "stable_local_measurement" if all(v["cv"] < .1 and v["relative_spread"] < .1 for v in values.values()) else "inconclusive",
                    "bootstrap_intervals_overlap": max(left[0], right[0]) <= min(left[1], right[1])}
            assessments.append(dict(storage=storage, producers=producers, phase=phase, metrics=assessed))
    report = {"trials": len(rows), "records_verified": sum(r["file_records_verified"] for r in rows), "pairs": 5,
              "affinity": AFFINITY, "source_sha256": provenance["after"]["source_sha256"], "binary_sha256": identities,
              "assessments": assessments, "scope": "Managed Logging, shared Memory/Mmap complete JSON with full metadata/system time, identical budgets, written/shutdown/cleanup. User PMU includes lifecycle and excludes kernel. No durable flush or cross-library ranking."}
    (HERE / f"{stem}-comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    for case in assessments:
        metric = case["metrics"]["instructions" if args.pmu else "written_records_per_sec"]
        print(case["storage"], case["producers"], case["phase"], metric["after_over_before"], metric["status"], flush=True)


if __name__ == "__main__":
    main()
