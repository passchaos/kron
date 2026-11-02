#!/usr/bin/env python3
"""Pair frozen public escaping probes, preserving every raw signed result."""
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


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", required=True)
    args = parser.parse_args()
    binaries = {label: getattr(args, label).resolve(strict=True) for label in ("before", "after")}
    identities = {label: sha(path) for label, path in binaries.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "manifest.json").write_text(json.dumps({"binaries": identities, "cpu": args.cpu,
        "driver_sha256": sha(Path(__file__)), "probe_sha256": sha(Path(__file__).with_name("escaping_probe.zig")),
        "loadavg_before": os.getloadavg(), "scope": "Public escaping only, 20 inputs × 4 operations, full output hashing; not full logging throughput"}, indent=2) + "\n")
    rows = []
    with (args.output / "results.jsonl").open("x") as output:
        for repetition in range(5):
            for label in (("before", "after") if repetition % 2 == 0 else ("after", "before")):
                if any(sha(path) != identities[key] for key, path in binaries.items()):
                    raise ValueError("binary changed")
                command = ["taskset", "-c", args.cpu, str(binaries[label])]
                try:
                    result = subprocess.run(command, text=True, capture_output=True, timeout=120)
                    (args.output / f"{repetition}-{label}.stdout.jsonl").write_text(result.stdout)
                    (args.output / f"{repetition}-{label}.stderr.log").write_text(result.stderr)
                    result.check_returncode()
                    samples = [json.loads(line) for line in result.stdout.splitlines()]
                    groups = collections.defaultdict(list)
                    if len(samples) != 400:
                        raise ValueError("missing escaping probe output")
                    for row in samples:
                        if row["benchmark"] != "public-escaping" or row["iterations"] != 10000:
                            raise ValueError("changed workload")
                        groups[(row["case"], row["operation"])].append(row)
                    expected = {(case, op) for case in range(20) for op in ("quoted_json", "quoted_text", "json_key", "json_member")}
                    if set(groups) != expected:
                        raise ValueError("changed case matrix")
                    for (case, op), group in groups.items():
                        if len(group) != 5 or {row["repetition"] for row in group} != set(range(5)):
                            raise ValueError("wrong internal repetitions")
                        if len({(row["checksum"], row["output_bytes"], row["input_bytes"]) for row in group}) != 1:
                            raise ValueError("unstable output")
                        row = {"label": label, "repetition": repetition, "case": case, "operation": op,
                               "input_bytes": group[0]["input_bytes"], "checksum": group[0]["checksum"],
                               "output_bytes": group[0]["output_bytes"], "ns_per_record": statistics.median(row["ns_per_record"] for row in group)}
                        rows.append(row)
                        output.write(json.dumps(row) + "\n")
                    output.flush()
                except (Exception, KeyboardInterrupt) as error:
                    def captured(value):
                        return value.decode(errors="replace") if isinstance(value, bytes) else value
                    (args.output / "failure.json").write_text(json.dumps({"command": command, "error": str(error),
                        "retry_started": False, "stdout_before_timeout": captured(getattr(error, "stdout", None)),
                        "stderr_before_timeout": captured(getattr(error, "stderr", None))}, indent=2) + "\n")
                    raise
                print(f"round {repetition}: {label}, 400 raw escaping batches checked", flush=True)
    groups = []
    for case, op in sorted({(r["case"], r["operation"]) for r in rows}):
        selected = {label: [r for r in rows if (r["label"], r["case"], r["operation"]) == (label, case, op)] for label in binaries}
        if len({(r["checksum"], r["output_bytes"]) for group in selected.values() for r in group}) != 1:
            raise ValueError("before/after output differs")
        groups.append({"case": case, "operation": op, "input_bytes": selected["before"][0]["input_bytes"],
                       "metrics": paired_metric(selected["after"], selected["before"], "ns_per_record", False)})
    (args.output / "summary.json").write_text(json.dumps({"groups": groups, "raw_batches": 4000,
        "all_output_checksums_equal": True, "loadavg_after": os.getloadavg(),
        "ratio_direction": "above one favors after; escaping only"}, indent=2) + "\n")


if __name__ == "__main__":
    main()
