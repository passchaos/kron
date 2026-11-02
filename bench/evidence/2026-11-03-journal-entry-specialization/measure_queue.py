#!/usr/bin/env python3
"""Paired queue-only controls; independently verify every reported checksum."""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "cpp_reference"))
from qualification import paired_metric


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", required=True)
    args = parser.parse_args()
    binaries = {label: getattr(args, label).resolve(strict=True) for label in ("before", "after")}
    hashes = {label: sha256(path) for label, path in binaries.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "manifest.json").write_text(json.dumps({
        "binary_sha256": hashes, "cpu": args.cpu, "driver_sha256": sha256(Path(__file__)),
        "probe_sha256": sha256(Path(__file__).with_name("queue_coordinate.zig")),
        "loadavg_before": os.getloadavg(), "capacities": [1, 2, 3, 7, 255, 256, 257, 512],
        "scope": "Journal queue only, 16B slots/8B payload, default CRC three checks, written release; no logging output, five paired independent invocations with five internal batches each",
    }, indent=2) + "\n")
    rows = []
    with (args.output / "results.jsonl").open("x") as output:
        for repetition in range(5):
            order = ("before", "after") if repetition % 2 == 0 else ("after", "before")
            for label in order:
                if any(sha256(path) != hashes[name] for name, path in binaries.items()):
                    raise ValueError("binary changed")
                command = ["taskset", "-c", args.cpu, str(binaries[label])]
                try:
                    result = subprocess.run(command, text=True, capture_output=True, timeout=120)
                    (args.output / f"{repetition}-{label}.stdout.jsonl").write_text(result.stdout)
                    (args.output / f"{repetition}-{label}.stderr.log").write_text(result.stderr)
                    result.check_returncode()
                    samples = [json.loads(line) for line in result.stdout.splitlines()]
                    if len(samples) != 40:
                        raise ValueError("missing queue-control samples")
                    groups = collections.defaultdict(list)
                    for row in samples:
                        if (row["benchmark"], row["iterations"], row["pending"], row["verify_crc"], row["clock_pairs"]) != ("queue-coordinate", 100000, 0, True, 1):
                            raise ValueError("changed control workload or CRC")
                        expected_first = row["capacity"] * 3 + 6 + row["repetition"] * 100000
                        expected_last = expected_first + 99999
                        if (row["first_sequence"], row["last_sequence"], row["checksum"]) != (
                            expected_first, expected_last, (expected_first + expected_last) * 100000 // 2,
                        ):
                            raise ValueError("wrong sequence or checksum")
                        groups[row["capacity"]].append(row)
                    if set(groups) != {1, 2, 3, 7, 255, 256, 257, 512}:
                        raise ValueError("changed capacity matrix")
                    for capacity, group in groups.items():
                        if len(group) != 5 or {row["repetition"] for row in group} != set(range(5)):
                            raise ValueError("wrong internal rounds")
                        row = {"label": label, "capacity": capacity, "repetition": repetition,
                               "ns_per_record": statistics.median(row["ns_per_record"] for row in group)}
                        rows.append(row)
                        output.write(json.dumps(row) + "\n")
                    output.flush()
                except (Exception, KeyboardInterrupt) as error:
                    def captured(value):
                        return value.decode(errors="replace") if isinstance(value, bytes) else value
                    (args.output / "failure.json").write_text(json.dumps({"command": command,
                        "error": str(error), "retry_started": False,
                        "stdout_before_timeout": captured(getattr(error, "stdout", None)),
                        "stderr_before_timeout": captured(getattr(error, "stderr", None))}, indent=2) + "\n")
                    raise
                print(f"round {repetition}: {label}, 40 raw controls verified", flush=True)
    report = {"raw_samples": 400, "all_sequence_checksums_verified": True, "groups": [],
              "loadavg_after": os.getloadavg(), "ratio_direction": "above one favors after; queue-only"}
    for capacity in (1, 2, 3, 7, 255, 256, 257, 512):
        selected = {label: [row for row in rows if row["label"] == label and row["capacity"] == capacity] for label in binaries}
        report["groups"].append({"capacity": capacity,
            "metrics": paired_metric(selected["after"], selected["before"], "ns_per_record", False)})
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
