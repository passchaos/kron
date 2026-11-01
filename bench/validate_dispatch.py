#!/usr/bin/env python3
"""Validate clock-only reports without asserting a timing advantage."""
import argparse
import json
import pathlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    options = parser.parse_args()
    binary = str(pathlib.Path(options.binary).resolve())
    completed = subprocess.run([binary, "--iterations=127", "--warmup=17", "--repetitions=3"], capture_output=True, text=True, timeout=20, check=True)
    rows = [json.loads(line) for line in completed.stdout.splitlines()]
    assert len(rows) == 12
    modes = ("dynamic", "std_io", "native", "none")
    for repetition in range(3):
        selected = rows[repetition * 4:(repetition + 1) * 4]
        assert [row["mode"] for row in selected] == [modes[(index + repetition) % 4] for index in range(4)]
        for row in selected:
            assert row["iterations"] == 127 and row["warmup_reads"] == 17
            assert row["dynamic_callback_from_runtime_factory"] == (row["mode"] == "dynamic")
            assert row["measurement_clock"] == "std.Io.Clock.awake"
            if row["status"] == "unsupported":
                assert row["mode"] == "native" and row["elapsed_ns"] is None
                continue
            assert row["status"] == "ok" and row["elapsed_ns"] > 0
            assert abs(row["ns_per_call"] - row["elapsed_ns"] / 127) < 1e-9
            assert row["clock_pair_mean_ns"] >= 0
            if row["mode"] == "none":
                assert row["checksum"] == 0 and row["timestamp_reads"] == 0
            else:
                assert row["checksum"] != 0 and row["timestamp_reads"] == 127
    explicit = subprocess.run([binary, "--iterations=127", "--warmup=0", "--repetitions=1", "--mode=dynamic"], capture_output=True, text=True, timeout=20, check=True)
    row = json.loads(explicit.stdout)
    assert row["mode"] == "dynamic" and row["warmup_reads"] == 0
    invalid = subprocess.run([binary, "--iterations=0"], capture_output=True, text=True, timeout=20)
    assert invalid.returncode != 0 and "InvalidBudget" in invalid.stderr
    print("clock dispatch: batch counts, checksums, order, controls and errors verified")


if __name__ == "__main__":
    main()
