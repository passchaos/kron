#!/usr/bin/env python3
"""Fixed request work across frozen versions, including the no-log baseline."""
import argparse
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("application_oracle", ROOT / "bench/application_compare.py")
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
sys.path.insert(0, str(ROOT / "bench/cpp_reference"))
from qualification import paired_metric


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    binaries = {key: getattr(args, key).resolve(strict=True) for key in ("before", "after")}
    identities = {key: sha(path) for key, path in binaries.items()}
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    affinity = [16, 18, 20, 22, 24, 26]
    options = dict(operations=12000, warmup=1000, repeats=5, sampled=False)
    manifest = dict(binaries={key: str(path) for key, path in binaries.items()}, binary_sha256=identities,
                    affinity=affinity, options=options, source_sha256={str(path.relative_to(ROOT)): sha(path) for path in sorted((ROOT / "src").rglob("*.zig"))},
                    oracle_sha256=sha(ROOT / "bench/application_compare.py"), driver_sha256=sha(Path(__file__)),
                    load_before=os.getloadavg(), scope="Synthetic compute/cache requests, P1/P4, every1/16, original public Runtime Memory/Mmap/shared/SPSC and no logger; whole completion and no-allocation checks, no cross-library or durable qualification.")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    cases = list(itertools.product(("compute", "cache"), (1, 4), (1, 16), oracle.MODES))
    rows = []
    with (output / "results.jsonl").open("x") as evidence:
        for repetition in range(options["repeats"]):
            ordered = cases if repetition % 2 == 0 else list(reversed(cases))
            for work, producers, every, (mode, storage) in ordered:
                oracle.reference(work, options["operations"], producers, options["warmup"])
                for label in (("before", "after") if repetition % 2 == 0 else ("after", "before")):
                    if any(sha(path) != identities[key] for key, path in binaries.items()):
                        raise ValueError("frozen binary changed")
                    temporary = Path(tempfile.mkdtemp(prefix="kron-member-application-"))
                    artifact = temporary / "output.jsonl"
                    command = ["taskset", "-c", ",".join(map(str, affinity)), str(binaries[label]), f"--output={artifact}", f"--mode={mode}",
                               f"--storage={storage if mode != 'none' else 'memory'}", f"--work={work}", f"--producers={producers}",
                               f"--every={every}", f"--operations={options['operations']}", f"--warmup={options['warmup']}", "--sampled=false"]
                    try:
                        process = subprocess.run(command, capture_output=True, text=True, timeout=120)
                        (temporary / "stdout.log").write_text(process.stdout)
                        (temporary / "stderr.log").write_text(process.stderr)
                        process.check_returncode()
                        row = json.loads(process.stdout)
                        oracle.verify(row, artifact, dict(work=work, mode=mode, producers=producers, log_every=every, sampled=False))
                        row.update(label=label, repetition=repetition, command=command, binary_sha256=identities[label])
                    except (Exception, KeyboardInterrupt) as error:
                        (output / "failure.json").write_text(json.dumps(dict(command=command, error=str(error), retained_directory=str(temporary), retry_started=False), indent=2) + "\n")
                        raise
                    evidence.write(json.dumps(row) + "\n")
                    evidence.flush()
                    rows.append(row)
                    shutil.rmtree(temporary)
            print(f"application pair {repetition + 1}/5: {len(rows)} request/JSON trials verified", flush=True)
    groups = []
    for work, producers, every, (mode, storage) in cases:
        selected = {key: [row for row in rows if (row["label"], row["work"], row["producers"], row["log_every"], row["mode"], row["storage"]) == (key, work, producers, every, mode, storage)] for key in binaries}
        metrics = {name: paired_metric(selected["after"], selected["before"], name, name == "application_operations_per_sec") for name in ("application_operations_per_sec", "total_ns", "lifecycle_ns")}
        no_logger = {}
        if mode != "none":
            for key in binaries:
                baseline = [row for row in rows if (row["label"], row["work"], row["producers"], row["log_every"], row["mode"]) == (key, work, producers, every, "none")]
                no_logger[key] = paired_metric(selected[key], baseline, "application_operations_per_sec")
        groups.append(dict(work=work, producers=producers, every=every, mode=mode, storage=storage, metrics=metrics, logged_vs_no_logger=no_logger))
    report = dict(trials=len(rows), operations_verified=sum(row["completed"] for row in rows), physical_records_verified=sum(row["file_records_verified"] for row in rows),
                  groups=groups, load_after=os.getloadavg(), ratio_direction="above one favors after for version pairs; above one favors logged for each no-logger comparison; scopes qualify separately")
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
