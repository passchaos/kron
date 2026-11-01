#!/usr/bin/env python3
"""Count actual producer futex calls and returns with unchanged own written target."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("label", choices=("before", "after"))
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("file_oracle", ROOT / "bench/cpp_reference/run.py")
    oracle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(oracle)
    binary = HERE / f"kron-ref-probe-{args.label}"
    identity = hashlib.sha256(binary.read_bytes()).hexdigest()
    rows = []
    destination = HERE / f"probe-{args.label}-results.jsonl"
    assert not destination.exists()
    temporary = Path(tempfile.mkdtemp(prefix="kron-queue-progress-probe-"))
    with destination.open("x") as output:
        for pair in range(3):
            for mode in ("async", "spsc"):
                for storage in ("memory", "mmap"):
                    directory = temporary / f"{pair}-{mode}-{storage}"
                    directory.mkdir()
                    artifact = directory / "events.jsonl"
                    command = ["taskset", "-c", "0,2,4,6,8,10", str(binary),
                               f"--output={artifact}", "--events=100000", "--warmup=1000",
                               "--producers=4", "--phase=batch", "--queue-slots=256",
                               f"--mode={mode}", f"--storage={storage}", "--schema=false", "--backend=portable"]
                    process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
                    (HERE / f"probe-{args.label}-{pair}-{mode}-{storage}.log").write_text(process.stdout + process.stderr)
                    if process.returncode:
                        raise RuntimeError(f"failed diagnostic artifact retained: {directory}")
                    row = json.loads(process.stdout)
                    oracle.verify(row, artifact, 100000, 1000)
                    counts = re.findall(r"QUEUE_WAIT producer=(\d+) calls=(\d+) unchanged_written=(\d+)", process.stderr)
                    assert len(counts) == 4
                    row.update(wait_counts=[dict(producer=int(p), calls=int(c), unchanged_written=int(u)) for p, c, u in counts],
                               pair=pair, command=command, binary_sha256=identity,
                               scope="instrumented diagnostic including warmup; unchanged target is an observation, not proof of syscall sleep or wake cause")
                    row["wait_calls"] = sum(x["calls"] for x in row["wait_counts"])
                    row["unchanged_written_returns"] = sum(x["unchanged_written"] for x in row["wait_counts"])
                    rows.append(row)
                    output.write(json.dumps(row) + "\n")
                    output.flush()
                    shutil.rmtree(directory)
                    print(mode, storage, pair, row["wait_calls"], row["unchanged_written_returns"], flush=True)
    temporary.rmdir()
    assert len(rows) == 12 and sum(r["file_records_verified"] for r in rows) == 1212000


if __name__ == "__main__":
    main()
