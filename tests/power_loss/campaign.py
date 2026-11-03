#!/usr/bin/env python3
"""Bounded repeated child-VM crash qualification, including journal ring reuse."""
import argparse
import hashlib
import json
import pathlib
import random
import subprocess
import time


def digest(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--testwriter", required=True, type=pathlib.Path)
    parser.add_argument("--kernel", required=True, type=pathlib.Path)
    parser.add_argument("--busybox", required=True, type=pathlib.Path)
    parser.add_argument("--output-dir", required=True, type=pathlib.Path)
    parser.add_argument("--runs", type=int, default=4)
    parser.add_argument("--filesystem", choices=("ext4", "xfs"), default="ext4")
    parser.add_argument("--seed", type=int, default=0x4B524F4E)
    parser.add_argument("--timeout", type=float, default=90)
    options = parser.parse_args()
    if not 1 <= options.runs <= 16:
        parser.error("runs must be between 1 and 16")
    root = pathlib.Path(__file__).resolve().parent
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / "results.json").exists():
        parser.error("refusing to overwrite existing campaign evidence")
    randomizer = random.Random(options.seed)
    acknowledgement_counts = [17, 31] + [randomizer.randint(1, 64) for _ in range(max(0, options.runs - 2))]
    acknowledgement_counts = acknowledgement_counts[:options.runs]
    report = {
        "scope": "abrupt child QEMU termination; not physical host power loss",
        "filesystem": options.filesystem,
        "seed": options.seed,
        "testwriter_sha256": digest(options.testwriter),
        "kernel_sha256": digest(options.kernel),
        "busybox_sha256": digest(options.busybox),
        "runs": [],
    }
    disk_mib = "512" if options.filesystem == "xfs" else "128"
    for index, acknowledged in enumerate(acknowledgement_counts):
        trial = output / f"run-{index:02d}-ack-{acknowledged}"
        command = [
            "python3", str(root / "vm_powerloss.py"),
            "--testwriter", str(options.testwriter.resolve()),
            "--kernel", str(options.kernel.resolve()),
            "--busybox", str(options.busybox.resolve()),
            "--work-dir", str(trial), "--disk-mib", disk_mib,
            "--filesystem", options.filesystem,
            "--kill-after-acks", str(acknowledged), "--schema",
            "--timeout", str(options.timeout),
        ]
        started = time.monotonic()
        completed = subprocess.run(command, capture_output=True, text=True, timeout=2 * options.timeout + 30)
        (output / f"run-{index:02d}.log").write_text(completed.stdout + completed.stderr)
        passed = completed.returncode == 0 and f"KRON_VERIFY_OK acked={acknowledged}" in completed.stdout
        report["runs"].append({
            "index": index, "acked": acknowledged, "passed": passed,
            "elapsed_seconds": time.monotonic() - started,
            "command": command, "returncode": completed.returncode,
            "evidence_directory": str(trial),
            "crash_image_sha256": digest(trial / "scratch.raw") if (trial / "scratch.raw").exists() else None,
        })
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"child VM run {index + 1}/{options.runs}: ACK {acknowledged}: {'PASS' if passed else 'FAIL'}", flush=True)
        if not passed:
            raise SystemExit(completed.stdout + completed.stderr)
    print(f"all {len(report['runs'])} bounded child-VM crash trials passed; evidence={output}")


if __name__ == "__main__":
    main()
