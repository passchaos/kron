#!/usr/bin/env python3
"""Frozen before/after whole-file measurements with optional user PMU."""
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
    parser.add_argument("--one-quantum-control", action="store_true", help="Compare original consumer-batches=1 with candidate default4")
    parser.add_argument("--long-p1", action="store_true")
    parser.add_argument("--long-mmap-p1", action="store_true")
    parser.add_argument("--capture-name", help="Distinct destination for a new complete capture; never overwrites")
    args = parser.parse_args()
    before = json.loads((HERE / "before-provenance.json").read_text())
    after = json.loads((HERE / "after-provenance.json").read_text())
    binaries = {"before": ROOT / before["binary_path"], "after": ROOT / after.get("binary_path", str((HERE / "kron-ref-after-final").relative_to(ROOT)))}
    identities = {"before": before["binary_sha256"], "after": after["binary_sha256"]}
    oracle = module("reference_oracle", ROOT / "bench/cpp_reference/run.py")
    regression = module("paired_summary", ROOT / "bench/regression.py")
    if args.one_quantum_control:
        assert not args.pmu and not args.long_p1 and not args.long_mmap_p1
        cases = [("spsc", storage, 4, schema) for storage in ("memory", "mmap") for schema in (False, True)]
        phases, events, stem = ["batch", "sampled"], 100000, "one-quantum-control"
    elif args.long_mmap_p1:
        assert not args.pmu and not args.long_p1
        cases = [("async", "mmap", 1, True)]
        phases, events, stem = ["batch"], 1000000, "long-mmap-p1"
    elif args.long_p1:
        assert not args.pmu
        cases = [("async", "memory", 1, True)]
        phases, events, stem = ["batch"], 1000000, "long-p1"
    elif args.pmu:
        cases = [("spsc", "memory", 4, False), ("spsc", "mmap", 4, False),
                 ("spsc", "memory", 4, True), ("spsc", "mmap", 4, True)]
        phases, events, stem = ["batch"], 300000, "pmu"
    else:
        cases = [(mode, storage, producers, True) for mode in ("async", "spsc")
                 for storage in ("memory", "mmap") for producers in (1, 4)]
        cases += [(mode, storage, producers, False) for mode in ("async", "spsc") for storage in ("memory", "mmap") for producers in (1, 4)]
        phases, events, stem = ["batch", "sampled"], 100000, "workflow"
    if args.capture_name:
        assert args.capture_name.replace("-", "").replace("_", "").isalnum()
        stem = args.capture_name

    def guard():
        assert all(sha(ROOT / key) == value for key, value in after["source_sha256"].items())
        assert all(sha(path) == identities[label] for label, path in binaries.items())

    trial_logs = HERE / "trials" / stem
    trial_logs.mkdir(parents=True, exist_ok=True)
    destination = HERE / f"{stem}-results.jsonl"
    assert not destination.exists(), "Preserve all prior captures"
    assert set(AFFINITY).issubset(os.sched_getaffinity(0))
    work = Path(tempfile.mkdtemp(prefix=f"kron-cross-queue-{stem}-"))
    rows = []
    with destination.open("x") as output:
        for pair in range(5):
            for mode, storage, producers, schema in cases:
                for phase in phases:
                    for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                        guard()
                        name = f"{stem}-{pair}-{mode}-{storage}-P{producers}-{schema}-{phase}-{label}"
                        directory = work / name
                        directory.mkdir()
                        artifact = directory / "output.jsonl"
                        command = ["taskset", "-c", ",".join(map(str, AFFINITY)), str(binaries[label]),
                                   f"--output={artifact}", f"--events={events}", "--warmup=1000",
                                   f"--producers={producers}", f"--phase={phase}", "--queue-slots=256",
                                   f"--mode={mode}", f"--storage={storage}", f"--schema={str(schema).lower()}",
                                   "--backend=portable"]
                        consumer_budget = 1 if args.one_quantum_control and label == "before" else 4
                        command.append(f"--consumer-batches={consumer_budget}")
                        if args.pmu:
                            command = ["perf", "stat", "-e", "cpu_core/instructions/u,cpu_core/cycles/u",
                                       "-x,", "-o", str(trial_logs / f"{name}.csv"), "--"] + command
                        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                        (trial_logs / f"{name}.log").write_text(process.stdout + process.stderr)
                        if process.returncode:
                            raise RuntimeError(f"failed workload retained at {directory}")
                        row = json.loads(process.stdout)
                        assert row["backend_requested"] == row["backend_selected"] == "portable"
                        assert row["metadata"] == "full" and row["event_clock"] == "std.Io_dynamic_system"
                        assert row["mode"] == mode and row["storage"] == storage and row["prepared_schema"] == schema
                        assert row["queue_slots"] == 256 and row["max_record_bytes"] == 512
                        assert row["file_buffer_bytes"] == 65536 and row["consumer_batches_per_queue"] == consumer_budget
                        oracle.verify(row, artifact, events, 1000)
                        if args.pmu:
                            counters = {}
                            for line in (trial_logs / f"{name}.csv").read_text().splitlines():
                                parts = line.split(",")
                                if len(parts) < 3 or not parts[0].isdigit():
                                    continue
                                for metric in ("instructions", "cycles"):
                                    if metric in parts[2]:
                                        counters[metric] = int(parts[0])
                            assert counters.keys() == {"instructions", "cycles"}
                            row.update(counters)
                        guard()
                        row.update(label=label, pair=pair, command=command,
                                   binary_sha256=identities[label], load_average=list(os.getloadavg()))
                        rows.append(row)
                        output.write(json.dumps(row) + "\n")
                        output.flush()
                        shutil.rmtree(directory)
                    print(f"{stem} pair {pair} {mode}/{storage} P{producers} schema={schema} {phase}: "
                          f"{len(rows)}/{len(cases) * len(phases) * 10} trials verified", flush=True)
    work.rmdir()
    assessments = []
    for mode, storage, producers, schema in cases:
        for phase in phases:
            selected = [r for r in rows if (r["mode"], r["storage"], r["producers"], r["prepared_schema"], r["phase"])
                        == (mode, storage, producers, schema, phase)]
            metrics = ["written_records_per_sec", "producer_wall_ns", "flush_ns", "shutdown_ns", "cleanup_ns",
                       "init_ns", "preparation_ns", "total_ns", "lifecycle_ns", "lifecycle_records_per_sec"]
            if phase == "sampled":
                metrics += ["p50_ns", "p99_ns", "p999_ns"]
            if args.pmu:
                metrics += ["instructions", "cycles"]
            assessed = {}
            for metric in metrics:
                values = {label: regression.summary([r[metric] for r in selected if r["label"] == label])
                          for label in binaries}
                left, right = (values[label]["median_bootstrap_ci95"] for label in binaries)
                assessed[metric] = {**values,
                    "after_over_before": values["after"]["median"] / values["before"]["median"] if values["before"]["median"] else None,
                    "status": "stable_local_measurement" if all(v["cv"] < .1 and v["relative_spread"] < .1 for v in values.values()) else "inconclusive",
                    "bootstrap_intervals_overlap": max(left[0], right[0]) <= min(left[1], right[1])}
            assessments.append(dict(mode=mode, storage=storage, producers=producers, schema=schema, phase=phase, metrics=assessed))
    report = {"trials": len(rows), "records_verified": sum(r["file_records_verified"] for r in rows),
              "pairs": 5, "affinity": AFFINITY, "noise_limit": .1, "source_sha256": after["source_sha256"],
              "binary_sha256": identities, "assessments": assessments,
              "scope": "Complete JSON, system time, identical queue/file budgets and written flush/shutdown/cleanup; "
                       "cross-queue checked windows candidate vs 714c470. User PMU includes initialization and excludes kernel work. No durable flush."}
    (HERE / f"{stem}-comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    for case in assessments:
        metric = case["metrics"]["instructions" if args.pmu else "written_records_per_sec"]
        print(case["mode"], case["storage"], case["producers"], case["schema"], case["phase"],
              metric["after_over_before"], metric["status"], flush=True)


if __name__ == "__main__":
    main()
