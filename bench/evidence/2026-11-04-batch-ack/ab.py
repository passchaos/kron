#!/usr/bin/env python3
"""Focused paired A/B for batch consumer acknowledgement.

Runs the frozen production reference and the candidate reference alternately
on the same E-core affinity, verifies every JSON record, and applies the same
10% spread / paired bootstrap qualification used by the Foundation matrix.
"""
import argparse
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "bench/cpp_reference"))
import run  # noqa: E402
from qualification import paired_metric  # noqa: E402

AFFINITY = "16,18,20,22,24,26"
EVENTS = 100_000
WARMUP = 1_000
REPEATS = 5


def cases():
    for mode in ("async", "spsc"):
        for storage in ("memory", "mmap"):
            for producers in (1, 4):
                for schema in (False, True):
                    yield {
                        "case": f"{mode}-{storage}-{'schema' if schema else 'inline'}-p{producers}",
                        "mode": mode,
                        "storage": storage,
                        "producers": producers,
                        "schema": schema,
                    }


def invoke(binary, case, repetition, artifact):
    command = [
        "taskset", "-c", AFFINITY, str(binary),
        f"--output={artifact}", f"--events={EVENTS}", f"--warmup={WARMUP}",
        f"--producers={case['producers']}", "--phase=batch", "--queue-slots=256",
        "--frontend=managed", f"--mode={case['mode']}", f"--storage={case['storage']}",
        f"--schema={'true' if case['schema'] else 'false'}",
    ]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
    if result.returncode != 0:
        raise RuntimeError(f"benchmark failed: {command}\n{result.stderr[-2000:]}")
    row = json.loads(result.stdout.strip().splitlines()[-1])
    run.verify(row, artifact, EVENTS, WARMUP)
    row["case"] = case["case"]
    row["repetition"] = repetition
    return row


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--output-dir", default=str(HERE))
    parser.add_argument("--summarize-only", action="store_true")
    options = parser.parse_args()
    output = pathlib.Path(options.output_dir)
    artifacts = output / "artifacts"
    artifacts.mkdir(parents=True, exist_ok=True)
    rows = []
    if options.summarize_only:
        rows = [json.loads(line) for line in (output / "results.jsonl").open()]
    else:
        for case in cases():
            for repetition in range(REPEATS):
                order = ("baseline", "candidate") if repetition % 2 == 0 else ("candidate", "baseline")
                for name in order:
                    binary = options.baseline if name == "baseline" else options.candidate
                    artifact = artifacts / f"{case['case']}-{name}-r{repetition}.jsonl"
                    for stale in (artifact, pathlib.Path(str(artifact) + ".journal")):
                        if stale.exists():
                            stale.unlink()
                    row = invoke(pathlib.Path(binary), case, repetition, artifact)
                    row["binary"] = name
                    rows.append(row)
                    for stale in (artifact, pathlib.Path(str(artifact) + ".journal")):
                        if stale.exists():
                            stale.unlink()
        with (output / "results.jsonl").open("w") as stream:
            for row in rows:
                stream.write(json.dumps(row, sort_keys=True) + "\n")

    grouped = {}
    for row in rows:
        grouped.setdefault((row["case"], row["binary"]), []).append(row)
    summary = {"affinity": AFFINITY, "events": EVENTS, "warmup": WARMUP, "repeats": REPEATS, "cases": []}
    for case in cases():
        baseline = grouped[(case["case"], "baseline")]
        candidate = grouped[(case["case"], "candidate")]
        metrics = {
            "written_records_per_sec": paired_metric(candidate, baseline, "written_records_per_sec"),
            "lifecycle_records_per_sec": paired_metric(candidate, baseline, "lifecycle_records_per_sec"),
            "total_ns": paired_metric(candidate, baseline, "total_ns", higher_is_better=False),
            "init_ns": paired_metric(candidate, baseline, "init_ns", higher_is_better=False),
            "shutdown_ns": paired_metric(candidate, baseline, "shutdown_ns", higher_is_better=False),
        }
        summary["cases"].append({"case": case["case"], "metrics": metrics})
    with (output / "summary.json").open("w") as stream:
        json.dump(summary, stream, indent=2, sort_keys=True)
        stream.write("\n")
    leads = negatives = inconclusive = 0
    for item in summary["cases"]:
        written = item["metrics"]["written_records_per_sec"]
        if written["assessment"] == "kron_leads":
            leads += 1
        elif written["assessment"] == "peer_leads":
            negatives += 1
        else:
            inconclusive += 1
    print(json.dumps({"cases": len(summary["cases"]), "candidate_leads": leads,
                      "baseline_leads": negatives, "inconclusive": inconclusive}, indent=2))


if __name__ == "__main__":
    main()
