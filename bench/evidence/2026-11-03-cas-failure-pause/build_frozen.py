#!/usr/bin/env python3
"""Freeze the two-line contention candidate before complete workflow timing."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHADOW = ROOT / ".zig-cache/cas-failure-pause"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    old = ROOT / ".zig-cache/crc-direct-tail"
    shutil.copytree(old / "before/src", SHADOW / "before/src", dirs_exist_ok=True)
    shutil.copy2(old / "before-reference", SHADOW / "before-reference")
    baseline = json.loads((HERE.parent / "2026-11-03-crc-direct-tail/candidate-provenance.json").read_text())
    if sha256(SHADOW / "before-reference") != baseline["binary_sha256"]["before-reference"]:
        raise ValueError("reused baseline changed")
    binary = SHADOW / "candidate-reference"
    if binary.exists():
        raise ValueError("refusing to overwrite frozen candidate")
    compiler = Path(shutil.which("zig")).resolve(strict=True)
    command = [str(compiler), "build-exe", "-O", "ReleaseFast", "--dep", "kron",
               f"-Mroot={ROOT / 'bench/cpp_reference/kron_reference.zig'}", "-O", "ReleaseFast",
               f"-Mkron={SHADOW / 'candidate/src/root.zig'}", f"-femit-bin={binary}"]
    (HERE / "candidate-reference-build-command.json").write_text(json.dumps(command, indent=2) + "\n")
    with (HERE / "candidate-reference-build.log").open("x") as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    sources = {}
    for label in ("before", "candidate"):
        source = SHADOW / label / "src"
        sources[label] = {str(p.relative_to(source)): sha256(p) for p in sorted(source.rglob("*")) if p.is_file()}
        with tarfile.open(HERE / f"{label}-source.tar.xz", "x:xz") as archive:
            archive.add(source, arcname="src")
    changed = [name for name in sorted(sources["before"]) if sources["before"][name] != sources["candidate"][name]]
    if sources["before"].keys() != sources["candidate"].keys() or changed != ["core/admission.zig", "journal/journal.zig"]:
        raise ValueError(f"unexpected source change: {changed}")
    provenance = {
        "baseline_commit": baseline["baseline_commit"], "source_sha256": sources,
        "changed_source_files": changed,
        "source_roots": {label: str(SHADOW / label / "src") for label in sources},
        "binary_sha256": {label: sha256(SHADOW / f"{label}-reference") for label in sources},
        "compiler": {"path": str(compiler), "sha256": sha256(compiler),
                     "version": subprocess.run([str(compiler), "version"], check=True, capture_output=True, text=True).stdout.strip()},
        "baseline_reference_reuse": "Frozen unmodified HEAD185e700 full Logging workflow binary; verified hash",
        "build_script_sha256": sha256(Path(__file__)), "all_compile_sessions_ended": True,
        "scope": "Only two CAS failure hints; no performance inference; production untouched",
    }
    (HERE / "candidate-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print("candidate full workflow binary frozen; build ended", flush=True)


if __name__ == "__main__":
    main()
