#!/usr/bin/env python3
"""Measure fresh mmap-journal runtime initialization before/after header-only initialization."""
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


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--record-bytes", type=int, required=True)
    parser.add_argument("--capture-name", required=True)
    parser.add_argument("--pairs", type=int, default=5)
    parser.add_argument("--events", type=int, default=1000)
    args = parser.parse_args()
    assert 512 <= args.record_bytes <= 1024 * 1024
    assert 5 <= args.pairs <= 9
    assert args.capture_name.replace("-", "").replace("_", "").isalnum()
    provenance = {label: json.loads((HERE / f"{label}-provenance.json").read_text()) for label in ("before", "after")}
    binaries = {label: ROOT / record["binary_path"] for label, record in provenance.items()}
    identities = {label: record["binary_sha256"] for label, record in provenance.items()}
    spec = importlib.util.spec_from_file_location("regression", ROOT / "bench/regression.py")
    regression = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(regression)
    assert set(AFFINITY).issubset(os.sched_getaffinity(0))
    destination = HERE / f"{args.capture_name}-results.jsonl"
    assert not destination.exists(), "Preserve prior captures"
    work = Path(tempfile.mkdtemp(prefix="kron-zero-init-"))
    rows = []
    with destination.open("x") as output:
        for pair in range(args.pairs):
            for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                if label == "after":
                    assert all(sha(ROOT / key) == value for key, value in provenance["after"]["source_sha256"].items())
                assert sha(binaries[label]) == identities[label]
                directory = work / f"{pair}-{label}"
                directory.mkdir()
                command = ["taskset", "-c", ",".join(map(str, AFFINITY)), str(binaries[label]),
                           "--mode=async", "--storage=mmap", "--sink=file", "--backend=portable",
                           f"--events={args.events}", "--warmup-events=100",
                           f"--max-record-bytes={args.record_bytes}", "--journal-slots=256",
                           f"--work-dir={directory}", "--output=json"]
                process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                (HERE / f"{args.capture_name}-trials").mkdir(exist_ok=True)
                (HERE / f"{args.capture_name}-trials" / f"{pair}-{label}.log").write_text(process.stdout + process.stderr)
                assert process.returncode == 0, process.stderr
                for line in process.stdout.splitlines():
                    row = json.loads(line)
                    assert row["status"] == "ok" and row["mode"] == "async"
                    assert row["journal_slots"] == 256
                    rows.append(dict(label=label, pair=pair, phase=row["phase"], init_ns=row["runtime_init_ns"],
                                     record_bytes=args.record_bytes, binary_sha256=identities[label], command=command))
                    output.write(json.dumps(rows[-1]) + "\n")
                    output.flush()
                shutil.rmtree(directory)
            print(f"init pair {pair}: {len(rows)} measurements", flush=True)
    work.rmdir()
    assessments = []
    for phase in ("sampled", "batch"):
        values = {}
        for label in ("before", "after"):
            selected = [r["init_ns"] for r in rows if r["label"] == label and r["phase"] == phase]
            values[label] = regression.summary(selected)
        left, right = (values[label]["median_bootstrap_ci95"] for label in ("before", "after"))
        assessments.append(dict(phase=phase, metrics={"init_ns": {
            **values, "after_over_before": values["after"]["median"] / values["before"]["median"],
            "overlap": max(left[0], right[0]) <= min(left[1], right[1]),
            "stable": all(v["cv"] < 0.1 and v["relative_spread"] < 0.1 for v in values.values()),
        }}))
    report = {"record_bytes": args.record_bytes, "journal_slots": 256, "pairs": args.pairs,
              "events": args.events, "affinity": AFFINITY, "binary_sha256": identities,
              "source_sha256": provenance["after"]["source_sha256"], "assessments": assessments,
              "scope": "Runtime creation only for async Mmap journal, file sink; includes file creation, preallocation, mapping, header initialization, publication and worker setup; excludes producer/consumer."}
    (HERE / f"{args.capture_name}-comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    for assessment in assessments:
        metric = assessment["metrics"]["init_ns"]
        print(assessment["phase"], metric["after_over_before"], metric["stable"], metric["overlap"], flush=True)


if __name__ == "__main__":
    main()
