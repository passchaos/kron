#!/usr/bin/env python3
"""Alternate frozen regex benchmarks on one CPU; retain every slow sample."""
import argparse
import hashlib
import json
import math
import os
import statistics
import subprocess
import unittest
from pathlib import Path

CASES = {
    "http_path", "severity_message", "long_literal_search", "nullable_loop",
    "overlapping_alternation", "state_budget", "dense_states", "nul_high_bytes",
}


def validate(rows, repetitions):
    expected = {(case, operation, repetition)
                for repetition in range(repetitions)
                for case in CASES for operation in ("pattern", "predicate")}
    expected |= {(case, "full_sync_json", repetition)
                 for repetition in range(repetitions)
                 for case in ("http_path", "severity_message")}
    result = {}
    for row in rows:
        key = (row["case"], row["operation"], row["repetition"])
        if key not in expected or key in result or row["benchmark"] != "regex":
            raise ValueError("unexpected or duplicate benchmark row")
        sample = row["sample"]
        for name in ("elapsed_ns", "attempts", "matches", "input_bytes", "written",
                     "output_bytes", "checksum", "runtime_allocations"):
            if type(sample[name]) is not int or sample[name] < 0:
                raise ValueError("invalid sample count")
        if not 4 <= sample["attempts"] <= 10000 or sample["attempts"] % 4 or sample["matches"] * 2 != sample["attempts"] or sample["elapsed_ns"] == 0:
            raise ValueError("invalid attempt or match accounting")
        if not math.isfinite(row["ns_per_attempt"]) or row["ns_per_attempt"] != sample["elapsed_ns"] / sample["attempts"]:
            raise ValueError("invalid batch timing")
        if key[1] == "full_sync_json":
            if sample["written"] != sample["matches"] or sample["output_bytes"] == 0 or sample["checksum"] == 0 or sample["runtime_allocations"] != 0:
                raise ValueError("incomplete or allocating JSON delivery")
        elif any(sample[name] for name in ("written", "output_bytes", "checksum", "runtime_allocations")):
            raise ValueError("isolated matcher reports output work")
        result[key] = row
    if result.keys() != expected:
        raise ValueError("missing benchmark rows")
    return result


def compare(left, right):
    if left.keys() != right.keys():
        raise ValueError("different benchmark shapes")
    for key in left:
        for name in ("optimize", "zig", "cpu", "clock_pairs", "producer_clock", "sink", "scope"):
            if left[key].get(name) != right[key].get(name):
                raise ValueError(f"changed measurement environment: {key} {name}")
        for name in left[key]["sample"]:
            if name != "elapsed_ns" and left[key]["sample"][name] != right[key]["sample"][name]:
                raise ValueError(f"changed workload or output: {key} {name}")


def run(args):
    destination = Path(args.output)
    destination.mkdir(parents=True, exist_ok=False)
    cpu = min(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None
    cpu = args.cpu if args.cpu is not None else cpu
    if cpu is not None:
        os.sched_setaffinity(0, {cpu})  # Inherited by each benchmark child.
    binaries = {label: Path(getattr(args, label)).resolve() for label in ("before", "after")}
    manifest = {"cpu": cpu, "pairs": args.pairs, "repetitions": args.repetitions,
                "iterations": args.iterations,
                "binaries": {label: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                             for label, path in binaries.items()},
                "scope": "batch match and full sync JSON counter; no async/file/tail ranking"}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    samples = {}
    for pair in range(args.pairs):
        rows = {}
        for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
            completed = subprocess.run([str(binaries[label]), f"--iterations={args.iterations}",
                                        f"--repetitions={args.repetitions}"],
                                       capture_output=True, text=True, timeout=120)
            (destination / f"{pair}-{label}.log").write_text(completed.stdout + completed.stderr)
            completed.check_returncode()
            rows[label] = validate([json.loads(line) for line in completed.stdout.splitlines()], args.repetitions)
            for key, row in rows[label].items():
                samples.setdefault(key[:2], {"before": [], "after": []})[label].append(row["ns_per_attempt"])
        compare(rows["before"], rows["after"])
        print(f"pair {pair + 1}/{args.pairs}: all counts and full JSON hashes agree", flush=True)
    summary = []
    for (case, operation), values in sorted(samples.items()):
        metrics = {}
        for label, data in values.items():
            median = statistics.median(data)
            metrics[label] = {"median_ns": median, "min_ns": min(data), "max_ns": max(data),
                              "relative_spread": (max(data) - min(data)) / median,
                              "cv": statistics.pstdev(data) / statistics.mean(data), "samples": len(data)}
        # Each process contributes its repetitions. Report spread over all
        # retained samples; noisy groups do not acquire a stable speed claim.
        stable = all(metric["relative_spread"] <= 0.1 and metric["cv"] <= 0.1 for metric in metrics.values())
        summary.append({"case": case, "operation": operation, **metrics,
                        "change_percent": (metrics["after"]["median_ns"] / metrics["before"]["median_ns"] - 1) * 100,
                        "status": "within_noise_budget" if stable else "inconclusive"})
    (destination / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


class Checks(unittest.TestCase):
    def rows(self):
        rows = []
        for repetition in range(5):
            for case in CASES:
                for operation in ("pattern", "predicate", "full_sync_json"):
                    if operation == "full_sync_json" and case not in ("http_path", "severity_message"):
                        continue
                    full = operation == "full_sync_json"
                    rows.append({"benchmark": "regex", "case": case, "operation": operation,
                                 "repetition": repetition, "ns_per_attempt": 25.0,
                                 "sample": {"elapsed_ns": 100, "attempts": 4, "matches": 2,
                                            "input_bytes": 16, "written": 2 if full else 0,
                                            "output_bytes": 256 if full else 0,
                                            "checksum": 123 if full else 0, "runtime_allocations": 0}})
        return rows

    def test_reject_missing_duplicate_counts_and_time(self):
        rows = self.rows()
        validate(rows, 5)
        for bad in (rows[:-1], rows + [rows[0]]):
            with self.assertRaises(ValueError):
                validate(bad, 5)
        for name, value in (("matches", 0), ("attempts", 3), ("elapsed_ns", 0)):
            bad = self.rows()
            bad[0]["sample"][name] = value
            with self.assertRaises(ValueError):
                validate(bad, 5)

    def test_reject_output_drift_and_allocation(self):
        left = validate(self.rows(), 5)
        bad = self.rows()
        row = next(row for row in bad if row["operation"] == "full_sync_json")
        row["sample"]["checksum"] += 1
        with self.assertRaises(ValueError):
            compare(left, validate(bad, 5))
        row["sample"]["runtime_allocations"] = 1
        with self.assertRaises(ValueError):
            validate(bad, 5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--before")
    parser.add_argument("--after")
    parser.add_argument("--output")
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--pairs", type=int, default=5)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=10000)
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=[__file__])
    elif not args.before or not args.after or not args.output or not 5 <= args.pairs <= 9 or not 5 <= args.repetitions <= 9 or not 4 <= args.iterations <= 10000:
        parser.error("requires both binaries, output and bounded repeated budgets")
    else:
        run(args)
