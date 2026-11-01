#!/usr/bin/env python3
"""Profile the frozen public full-file workflow and verify every output row."""
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
EVENTS = 1_000_000
AFFINITY = [0, 2, 4, 6, 8, 10]
CASES = [(mode, storage, False) for mode in ("async", "spsc")
         for storage in ("memory", "mmap")] + [("spsc", storage, True)
         for storage in ("memory", "mmap")]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    identity = json.loads((HERE / "before-provenance.json").read_text())
    binary = ROOT / identity["binary_path"]
    spec = importlib.util.spec_from_file_location("profile_oracle", ROOT / "bench/cpp_reference/run.py")
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)

    def guard():
        assert sha(binary) == identity["binary_sha256"]
        assert all(sha(ROOT / key) == value for key, value in identity["source_sha256"].items())

    assert set(AFFINITY).issubset(os.sched_getaffinity(0))
    destination = HERE / "profile-results.jsonl"
    assert not destination.exists(), "Preserve an existing capture"
    work = Path(tempfile.mkdtemp(prefix="kron-post-coalescing-profile-"))
    with destination.open("x") as output:
        for mode, storage, schema in CASES:
            guard()
            name = f"{mode}-{storage}-{'schema' if schema else 'inline'}"
            directory = work / name
            directory.mkdir()
            artifact = directory / "output.jsonl"
            command = ["perf", "record", "-e", "cycles:u", "-F", "1999", "-g", "-o",
                       str(HERE / f"{name}.data"), "--", "taskset", "-c",
                       ",".join(map(str, AFFINITY)), str(binary), f"--output={artifact}",
                       f"--events={EVENTS}", "--warmup=1000", "--producers=4", "--phase=batch",
                       "--queue-slots=256", f"--mode={mode}", f"--storage={storage}",
                       f"--schema={str(schema).lower()}", "--backend=portable"]
            process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
            (HERE / f"{name}.stderr.log").write_text(process.stderr)
            (HERE / f"{name}.stdout.json").write_text(process.stdout)
            if process.returncode:
                raise RuntimeError(f"profile failed; workload retained at {directory}")
            row = json.loads(process.stdout)
            assert row["backend_selected"] == "portable"
            oracle.verify(row, artifact, EVENTS, 1000)
            guard()
            row.update(command=command, binary_sha256=identity["binary_sha256"],
                       load_average=list(os.getloadavg()))
            output.write(json.dumps(row) + "\n")
            output.flush()
            report = subprocess.run(["perf", "report", "--stdio", "-i", str(HERE / f"{name}.data"),
                                     "--sort", "symbol", "-n", "--percent-limit", "0.5",
                                     "--call-graph", "none"], capture_output=True, text=True, check=True)
            (HERE / f"{name}.report.txt").write_text(report.stdout)
            (HERE / f"{name}.report.stderr.log").write_text(report.stderr)
            shutil.rmtree(directory)
            print(f"{name}: {row['file_records_verified']} full records independently verified", flush=True)
    work.rmdir()


if __name__ == "__main__":
    main()
