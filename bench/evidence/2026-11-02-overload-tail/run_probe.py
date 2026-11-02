#!/usr/bin/env python3
"""Repeat the slow-sink overload probe and preserve all raw rows."""
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BINARY = ROOT / ".zig-cache/kron-overload-probe"
AFFINITY = "16,18,20,22,24,26"


def main():
    destination = HERE / "results.jsonl"
    assert not destination.exists(), "Preserve prior capture"
    rows = []
    with destination.open("x") as output:
        for overflow in ("block", "drop", "fallback"):
            for producers in (1, 4):
                for trial in range(5):
                    command = ["taskset", "-c", AFFINITY, str(BINARY), overflow,
                               str(producers), "1000", "200000"]
                    run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    assert run.returncode == 0, run.stderr
                    row = json.loads(run.stdout)
                    row.update(trial=trial)
                    rows.append(row)
                    output.write(json.dumps(row) + "\n")
                    output.flush()
    print(f"overload probe: {len(rows)} rows verified")


if __name__ == "__main__":
    main()
