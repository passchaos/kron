#!/usr/bin/env python3
"""Compare requested Runtime allocations from two frozen executables."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
CASES = (("sync", 0), ("memory", 0), ("memory", 1), ("memory", 4),
         ("memory", 64), ("mmap", 0), ("mmap", 4))
FIELDS = ("requested_live_bytes", "initialization_allocations", "runtime_owner_bytes",
          "queue_reserved_bytes", "journal_reserved_bytes", "initialization_ns")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--capture-name", default="resources-repeat")
    args = parser.parse_args()
    assert args.capture_name.replace("-", "").replace("_", "").isalnum()
    binaries = {label: getattr(args, label).resolve(strict=True) for label in ("before", "after")}
    identities = {label: sha(path) for label, path in binaries.items()}
    destination = HERE / f"{args.capture_name}.jsonl"
    assert not destination.exists(), "Preserve all prior captures"
    logs = HERE / "trials" / args.capture_name
    logs.mkdir(parents=True, exist_ok=True)
    rows = []
    with destination.open("x") as output:
        for pair in range(5):
            for mode, budget in CASES:
                for label in (("before", "after") if pair % 2 == 0 else ("after", "before")):
                    assert all(sha(path) == identities[key] for key, path in binaries.items())
                    with tempfile.TemporaryDirectory(prefix="kron-runtime-resources-") as folder:
                        command = [str(binaries[label]), mode, folder, str(budget)]
                        run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                    name = f"{pair}-{mode}-{budget}-{label}"
                    (logs / f"{name}.log").write_text(run.stdout + run.stderr)
                    assert run.returncode == 0, name
                    row = json.loads(run.stdout)
                    assert row["benchmark"] == "runtime_requested_resources"
                    assert (row["mode"], row["thread_budget"]) == (mode, budget)
                    assert row["allocator_freed_all"] is True and row["written"] == 1
                    assert all(sha(path) == identities[key] for key, path in binaries.items())
                    row.update(label=label, pair=pair, command=command, binary_sha256=identities[label])
                    rows.append(row)
                    output.write(json.dumps(row) + "\n")
                    output.flush()
    groups = defaultdict(list)
    for row in rows:
        groups[(row["mode"], row["thread_budget"], row["label"])].append(row)
    comparison = []
    for mode, budget in CASES:
        record = dict(mode=mode, thread_budget=budget)
        for field in FIELDS:
            record[field] = {label: statistics.median(row[field] for row in groups[(mode, budget, label)])
                             for label in binaries}
        comparison.append(record)
    report = {"trials": len(rows), "binary_sha256": identities, "comparison": comparison,
              "scope": "Runtime allocator requested live heap and allocation count at initialization; "
                       "not RSS or all native/OS resources. Caller supplies frozen source/build provenance."}
    (HERE / f"{args.capture_name}-comparison.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
