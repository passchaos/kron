#!/usr/bin/env python3
"""Compare frozen CRC binaries with unchanged journal partitions and checksums."""
import argparse
import collections
import hashlib
import json
import lzma
import os
from pathlib import Path
import platform
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
    binaries = {name: getattr(args, name).resolve(strict=True) for name in ("before", "after")}
    identities = {name: sha256(path) for name, path in binaries.items()}
    support = Path(__file__).resolve().parent
    lengths = json.loads((support / "extended-cases.json").read_text())["lengths"]
    expected = {(length, schema) for length in lengths for schema in (False, True)}
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "binary_sha256": identities,
        "binary_paths": {name: str(path) for name, path in binaries.items()},
        "driver_sha256": sha256(Path(__file__)),
        "qualification_sha256": sha256(support.parents[1] / "cpp_reference/qualification.py"),
        "primitive_sha256": sha256(support / "primitive.zig"),
        "case_manifest_sha256": sha256(support / "extended-cases.json"),
        "lengths": lengths,
        "cpu": args.cpu,
        "host": platform.uname()._asdict(),
        "loadavg_before": os.getloadavg(),
        "scope": "CRC only: original 20B header, optional 24B reference, payload; five paired invocations, five internal batches of 10000, 16 rotating alignments. No logging throughput claim.",
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    rows = []
    with (args.output / "results.jsonl").open("x") as evidence:
        for repetition in range(5):
            order = ("before", "after") if repetition % 2 == 0 else ("after", "before")
            for label in order:
                if any(sha256(path) != identities[name] for name, path in binaries.items()):
                    raise ValueError("binary changed during measurement")
                command = ["taskset", "-c", args.cpu, str(binaries[label])]
                try:
                    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    (args.output / f"{repetition}-{label}.stdout.jsonl.xz").write_bytes(lzma.compress(result.stdout.encode()))
                    (args.output / f"{repetition}-{label}.stderr.log").write_text(result.stderr)
                    result.check_returncode()
                    samples = [json.loads(line) for line in result.stdout.splitlines()]
                    groups = collections.defaultdict(list)
                    for sample in samples:
                        if (sample["benchmark"], sample["iterations"], sample["clock_pairs"], sample["heap_allocations_in_batch"]) != ("journal-crc", 10000, 1, 0):
                            raise ValueError("changed primitive workload")
                        groups[(sample["payload_bytes"], sample["schema"])].append(sample)
                    if set(groups) != expected or len(samples) != len(expected) * 5:
                        raise ValueError("missing or extra primitive case")
                    for (length, schema), group in groups.items():
                        if (len(group) != 5 or {r["repetition"] for r in group} != set(range(5))
                                or len({r["checksum"] for r in group}) != 1):
                            raise ValueError("invalid repetition or checksum")
                        row = {"label": label, "repetition": repetition, "length": length, "schema": schema,
                               "ns_per_record": statistics.median(r["ns_per_record"] for r in group),
                               "checksum": group[0]["checksum"]}
                        rows.append(row)
                        evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                except (Exception, KeyboardInterrupt) as error:
                    def captured(value):
                        return value.decode(errors="replace") if isinstance(value, bytes) else value
                    (args.output / "failure.json").write_text(json.dumps({"command": command, "error": str(error),
                        "retry_started": False, "stdout_before_timeout": captured(getattr(error, "stdout", None)),
                        "stderr_before_timeout": captured(getattr(error, "stderr", None))}, indent=2) + "\n")
                    raise
                print(f"round {repetition}: {label}, {len(samples)} raw samples checked", flush=True)
    groups = []
    for length, schema in sorted(expected):
        selected = {label: [r for r in rows if (r["label"], r["length"], r["schema"]) == (label, length, schema)] for label in binaries}
        if len({r["checksum"] for group in selected.values() for r in group}) != 1:
            raise ValueError("before/after checksum mismatch")
        groups.append({"length": length, "schema": schema,
                       "metrics": paired_metric(selected["after"], selected["before"], "ns_per_record", False)})
    report = {"groups": groups, "rows": len(rows), "raw_samples": len(expected) * 5 * 10,
              "checksum_pairs_equal": True, "loadavg_after": os.getloadavg(),
              "ratio_direction": "above one favors after; primitive only"}
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
