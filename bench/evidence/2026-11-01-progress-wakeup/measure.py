#!/usr/bin/env python3
"""Paired full-file workflow; use the existing independent output oracle."""
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
CASES = [(mode, storage, producers, False)
         for mode in ("async", "spsc") for storage in ("memory", "mmap")
         for producers in (1, 4)]
BINARIES = {label: HERE / f"kron-ref-{label}" for label in ("before", "after")}
TOTAL_TRIALS = len(CASES) * 2 * 2 * 5



def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    oracle = module("encoder_workflow_oracle", ROOT / "bench/cpp_reference/run.py")
    regression = module("encoder_summary", ROOT / "bench/regression.py")
    before = json.loads((HERE / "before-provenance.json").read_text())
    after = json.loads((HERE / "after-provenance.json").read_text())
    watched = after["source_sha256"]
    identities = {"before": before["binary_sha256"], "after": after["binary_sha256"]}

    def guard():
        assert all(sha(ROOT / path) == value for path, value in watched.items())
        assert all(sha(path) == identities[label] for label, path in BINARIES.items())

    assert set(AFFINITY).issubset(os.sched_getaffinity(0))
    report = HERE / "workflow-results.jsonl"
    assert not report.exists(), "Do not restart or overwrite an existing capture"
    work = Path(tempfile.mkdtemp(prefix="kron-progress-wakeup-workflow-"))
    rows = []
    with report.open("x") as output:
        for repetition in range(5):
            for mode, storage, producers, schema in CASES:
                for phase in ("batch", "sampled"):
                    labels = ("before", "after") if repetition % 2 == 0 else ("after", "before")
                    for label in labels:
                        guard()
                        directory = work / f"{repetition}-{mode}-{storage}-{producers}-{schema}-{phase}-{label}"
                        directory.mkdir()
                        artifact = directory / "output.jsonl"
                        command = [
                            "taskset", "-c", ",".join(map(str, AFFINITY)), str(BINARIES[label]),
                            f"--output={artifact}", "--events=100000", "--warmup=1000",
                            f"--producers={producers}", f"--phase={phase}", "--queue-slots=256",
                            f"--mode={mode}", f"--storage={storage}", f"--schema={str(schema).lower()}",
                        ]
                        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                        if process.returncode:
                            (directory / "stdout.log").write_text(process.stdout)
                            (directory / "stderr.log").write_text(process.stderr)
                            raise RuntimeError(f"workflow failed; evidence retained at {directory}")
                        row = json.loads(process.stdout)
                        assert row["metadata"] == "full" and row["optimize"] == "ReleaseFast"
                        assert row["mode"] == mode and row["storage"] == storage
                        assert row["prepared_schema"] == schema and row["producers"] == producers
                        assert row["queue_slots"] == 256 and row["max_record_bytes"] == 512
                        assert row["event_clock"] == "std.Io_dynamic_system"
                        oracle.verify(row, artifact, 100000, 1000)
                        guard()
                        row.update(label=label, repetition=repetition, command=command,
                                   binary_sha256=identities[label])
                        output.write(json.dumps(row) + "\n")
                        output.flush()
                        rows.append(row)
                        shutil.rmtree(directory)
                    print(f"queue pair {repetition} {mode} {storage} P{producers} prepared={schema} {phase}: "
                          f"{len(rows)}/{TOTAL_TRIALS} trials; every output record verified", flush=True)
    guard()
    assert len(rows) == TOTAL_TRIALS
    assert sum(row["file_records_verified"] for row in rows) == TOTAL_TRIALS * 101000
    assessments = []
    for mode, storage, producers, schema in CASES:
        for phase in ("batch", "sampled"):
            selected = [row for row in rows if (row["mode"], row["storage"], row["producers"],
                        row["prepared_schema"], row["phase"]) == (mode, storage, producers, schema, phase)]
            metrics = ["written_records_per_sec", "producer_wall_ns", "flush_ns", "shutdown_ns",
                       "cleanup_ns", "init_ns", "preparation_ns", "total_ns", "lifecycle_ns",
                       "lifecycle_records_per_sec"]
            if phase == "sampled":
                metrics += ["p50_ns", "p99_ns", "p999_ns"]
            summarized = {}
            for metric in metrics:
                values = {label: regression.summary([row[metric] for row in selected if row["label"] == label])
                          for label in ("before", "after")}
                stable = all(value["cv"] < 0.1 and value["relative_spread"] < 0.1 for value in values.values())
                left, right = (values[label]["median_bootstrap_ci95"] for label in ("before", "after"))
                summarized[metric] = {
                    **values,
                    "after_over_before": values["after"]["median"] / values["before"]["median"]
                        if values["before"]["median"] else None,
                    "status": "stable_local_measurement" if stable else "inconclusive",
                    "bootstrap_intervals_overlap": max(left[0], right[0]) <= min(left[1], right[1]),
                }
            assessments.append(dict(mode=mode, storage=storage, producers=producers, schema=schema,
                                    phase=phase, metrics=summarized))
    result = {
        "trials": TOTAL_TRIALS, "records_verified": TOTAL_TRIALS * 101000, "pairs": 5, "affinity": AFFINITY,
        "noise_limit": 0.1, "source_sha256": watched, "binary_sha256": identities,
        "scope": "Same full JSON, system clocks, queue/file budgets and written flush/shutdown/cleanup; "
                 "only progress waiter registration and conditional futex wake changed. Memory/Mmap records, queue and file budgets, per-record validation and flush/reclaim remain.",
        "assessments": assessments,
    }
    (HERE / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
    work.rmdir()
    for entry in assessments:
        if entry["phase"] == "batch":
            metric = entry["metrics"]["written_records_per_sec"]
            print(entry["mode"], entry["storage"], entry["producers"], entry["schema"],
                  round(metric["before"]["median"]), "->", round(metric["after"]["median"]),
                  metric["status"], flush=True)


if __name__ == "__main__":
    main()
