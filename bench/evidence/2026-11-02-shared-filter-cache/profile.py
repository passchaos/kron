#!/usr/bin/env python3
"""Repeat the frozen baseline user-cycle profile with actual JSON verification."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-name", required=True)
    args = parser.parse_args()
    assert args.capture_name.replace("-", "").replace("_", "").isalnum()
    output = HERE / args.capture_name
    output.mkdir()
    work = ROOT / ".zig-cache" / args.capture_name
    work.mkdir()
    provenance = json.loads((HERE / "before-provenance.json").read_text())
    binary = ROOT / provenance["binary_path"]
    spec = importlib.util.spec_from_file_location("reference_oracle", ROOT / "bench/cpp_reference/run.py")
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    rows = []
    for storage, producers in (("memory", 1), ("memory", 4), ("mmap", 1), ("mmap", 4)):
        assert hashlib.sha256(binary.read_bytes()).hexdigest() == provenance["binary_sha256"]
        name = f"{storage}-P{producers}"
        artifact, data = work / f"{name}.jsonl", work / f"{name}.data"
        command = ["perf", "record", "-e", "cpu_core/cycles/u", "-F", "997", "-g", "--call-graph", "dwarf,16384",
                   "-o", str(data), "--", "taskset", "-c", "0,2,4,6,8,10", str(binary), f"--output={artifact}",
                   "--frontend=managed", "--events=1000000", "--warmup=1000", f"--producers={producers}",
                   "--phase=batch", "--queue-slots=256", "--mode=async", f"--storage={storage}", "--schema=false", "--backend=portable"]
        run = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (output / f"{name}.log").write_text(run.stdout + run.stderr)
        assert run.returncode == 0, name
        row = json.loads(run.stdout)
        assert row["frontend"] == "managed" and row["optimize"] == "ReleaseFast"
        oracle.verify(row, artifact, 1000000, 1000)
        row.update(command=command, binary_sha256=provenance["binary_sha256"])
        rows.append(row)
        (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
        for children, suffix in ((False, "self"), (True, "children")):
            report = subprocess.run(["perf", "report", "--stdio", "--percent-limit", "0.3",
                                     "--children" if children else "--no-children", "--call-graph", "none", "-i", str(data)],
                                    capture_output=True, text=True, timeout=30)
            (output / f"{name}-{suffix}.txt").write_text(report.stdout + report.stderr)
            assert report.returncode == 0
        artifact.unlink()
        print(name, "full JSON verified, profile retained", flush=True)


if __name__ == "__main__":
    main()
