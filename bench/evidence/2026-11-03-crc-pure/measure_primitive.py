#!/usr/bin/env python3
"""Paired independent CRC-shaped invocations; exact old header partitions."""
import argparse, collections, hashlib, json, pathlib, statistics, subprocess, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "cpp_reference"))
from qualification import paired_metric

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binaries", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--cpu", default="30")
    args = parser.parse_args()
    variants = ["before", "pure", "vex"]
    binaries = {label: (args.binaries / (label + "-bench")).resolve(strict=True) for label in variants}
    identities = {label: hashlib.sha256(binary.read_bytes()).hexdigest() for label, binary in binaries.items()}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "manifest.json").write_text(json.dumps({"binaries": identities, "cpu": args.cpu, "scope": "CRC only, 20B header + optional 24B schema + payload. Five invocations, five internal repetitions, 25 lengths, both versions, 16 rotating alignments. Not logging throughput."}, indent=2) + "\n")
    rows = []
    with (args.output / "results.jsonl").open("x") as evidence:
        for repetition in range(5):
            ordered = variants if repetition % 2 == 0 else variants[::-1]
            for label in ordered:
                if hashlib.sha256(binaries[label].read_bytes()).hexdigest() != identities[label]:
                    raise ValueError("binary changed")
                command = ["taskset", "-c", args.cpu, str(binaries[label])]
                result = subprocess.run(command, capture_output=True, text=True, timeout=45)
                (args.output / f"{repetition}-{label}.log").write_text(result.stdout + result.stderr)
                result.check_returncode()
                samples = [json.loads(line) for line in result.stdout.splitlines()]
                if len(samples) != 250: raise ValueError("missing primitive cases")
                groups = collections.defaultdict(list)
                for row in samples: groups[(row["payload_bytes"], row["schema"])].append(row)
                if len(groups) != 50 or any(len(group) != 5 for group in groups.values()): raise ValueError("case counts")
                for (length, schema), group in groups.items():
                    if len({row["checksum"] for row in group}) != 1: raise ValueError("unstable checksum")
                    row = {"label": label, "repetition": repetition, "length": length, "schema": schema, "ns_per_record": statistics.median(row["ns_per_record"] for row in group), "checksum": group[0]["checksum"]}
                    rows.append(row); evidence.write(json.dumps(row) + "\n")
                evidence.flush()
                print(repetition, label, "250 cases completed", flush=True)
    groups = []
    for length, schema in sorted({(r["length"], r["schema"]) for r in rows}):
        selected = {label: [r for r in rows if (r["label"], r["length"], r["schema"]) == (label, length, schema)] for label in variants}
        if len({r["checksum"] for selected_ in selected.values() for r in selected_}) != 1: raise ValueError("candidate CRC differs")
        metrics = {label: paired_metric(selected[label], selected["before"], "ns_per_record", False) for label in variants[1:]}
        groups.append({"length": length, "schema": schema, "metrics": metrics})
    report = {"groups": groups, "rows": len(rows), "raw_samples": 3750, "checksum_pairs_equal": True, "ratio_direction": "above one favors candidate; local primitive qualification only"}
    (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
if __name__ == "__main__": main()
