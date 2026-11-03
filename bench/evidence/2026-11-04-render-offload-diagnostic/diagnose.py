#!/usr/bin/env python3
"""Diagnostic-only render cost isolation.

The `norender` binary replaces the consumer JSON renderer with a fixed
299-byte payload; the `prodrender` binary additionally renders the same JSON
on each producer and discards it. Outputs are intentionally not verified:
this measures the throughput ceiling, not output correctness.
"""
import json
import pathlib
import statistics
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = pathlib.Path("/tmp/kron-render-diag")
AFFINITY = "16,18,20,22,24,26"


def run(binary, name, producers, storage, rep):
    OUT.mkdir(exist_ok=True)
    artifact = OUT / f"{name}-{producers}-{storage}-r{rep}.jsonl"
    for path in (artifact, pathlib.Path(str(artifact) + ".journal")):
        if path.exists():
            path.unlink()
    command = [
        "taskset", "-c", AFFINITY, str(binary),
        f"--output={artifact}", "--events=100000", "--warmup=1000",
        f"--producers={producers}", "--phase=batch", "--queue-slots=256",
        "--frontend=managed", "--mode=async", f"--storage={storage}", "--schema=false",
    ]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
    if result.returncode != 0:
        raise RuntimeError(result.stderr[-2000:])
    row = json.loads(result.stdout.strip().splitlines()[-1])
    for path in (artifact, pathlib.Path(str(artifact) + ".journal")):
        if path.exists():
            path.unlink()
    row["binary"] = name
    row["diagnostic_case"] = f"p{producers}-{storage}"
    row["repetition"] = rep
    return row


def main():
    binaries = {
        "prod": ROOT / "bench/evidence/2026-11-04-current-foundation-full-ecore/reference-kron",
        "norender": pathlib.Path("/tmp/reference-kron-diag-norender"),
        "prodrender": pathlib.Path("/tmp/reference-kron-diag-producer-render"),
    }
    rows = []
    for rep in range(7):
        order = list(binaries.items()) if rep % 2 == 0 else list(reversed(list(binaries.items())))
        for name, binary in order:
            rows.append(run(binary, name, 4, "mmap", rep))
    with (HERE / "results.jsonl").open("w") as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True) + "\n")
    grouped = {}
    for row in rows:
        grouped.setdefault((row["binary"], row["diagnostic_case"]), []).append(row["written_records_per_sec"])
    summary = {f"{name}/{case}": {"runs": [round(value / 1e6, 3) for value in values],
                                  "median_m_records_per_sec": round(statistics.median(values) / 1e6, 3)}
               for (name, case), values in sorted(grouped.items())}
    (HERE / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
