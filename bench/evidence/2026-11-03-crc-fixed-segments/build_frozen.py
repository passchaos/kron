#!/usr/bin/env python3
"""Build the owning-entry probe and candidate workflow before any timing."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHADOW = ROOT / ".zig-cache/crc-fixed-segments"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    compiler = Path(shutil.which("zig")).resolve(strict=True)
    version = subprocess.run([str(compiler), "version"], check=True, capture_output=True, text=True).stdout.strip()
    baseline = json.loads((HERE.parent / "2026-11-03-crc-direct-tail/candidate-provenance.json").read_text())
    if sha256(SHADOW / "before-reference") != baseline["binary_sha256"]["before-reference"]:
        raise ValueError("reused workflow baseline binary changed")
    commands = [
        (f"{label}-primitive", [str(compiler), "build-exe", "-O", "ReleaseFast",
                              f"-Mroot={SHADOW / label / 'src/primitive.zig'}",
                              f"-femit-bin={SHADOW / (label + '-bench')}"])
        for label in ("before", "candidate")
    ]
    commands.append(("candidate-reference", [str(compiler), "build-exe", "-O", "ReleaseFast", "--dep", "kron",
                                             f"-Mroot={ROOT / 'bench/cpp_reference/kron_reference.zig'}",
                                             "-O", "ReleaseFast", f"-Mkron={SHADOW / 'candidate/src/root.zig'}",
                                             f"-femit-bin={SHADOW / 'candidate-reference'}"]))
    for name, command in commands:
        binary = Path(command[-1].split("=", 1)[1])
        if binary.exists():
            raise ValueError(f"refusing to overwrite frozen binary: {binary}")
        (HERE / f"{name}-build-command.json").write_text(json.dumps(command, indent=2) + "\n")
        with (HERE / f"{name}-build.log").open("x") as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        print(f"{name}: build completed", flush=True)
    trees = {}
    for label in ("before", "candidate"):
        source = SHADOW / label / "src"
        trees[label] = {str(path.relative_to(source)): sha256(path) for path in sorted(source.rglob("*"))
                        if path.is_file() and path.name != "primitive.zig"}
        if sha256(source / "primitive.zig") != sha256(HERE / "primitive.zig"):
            raise ValueError("probe source differs between binaries")
        with tarfile.open(HERE / f"{label}-source.tar.xz", "x:xz") as archive:
            archive.add(source, arcname="src")
    changed = [name for name in sorted(trees["before"]) if trees["before"][name] != trees["candidate"][name]]
    expected = ["journal/format.zig", "platform/crc32.zig", "platform/crc32_pclmul.zig"]
    if changed != expected or trees["before"].keys() != trees["candidate"].keys():
        raise ValueError(f"unexpected source difference: {changed}")
    provenance = {
        "baseline_commit": baseline["baseline_commit"],
        "source_roots": {label: str(SHADOW / label / "src") for label in trees},
        "source_sha256": trees,
        "changed_source_files": changed,
        "generated_same_source_probe": "src/primitive.zig",
        "probe_sha256": sha256(HERE / "primitive.zig"),
        "binary_sha256": {name: sha256(SHADOW / name) for name in
                          ("before-reference", "candidate-reference", "before-bench", "candidate-bench")},
        "compiler": {"path": str(compiler), "sha256": sha256(compiler), "version": version},
        "baseline_reference_reuse": "Unmodified frozen HEAD185e700 binary; exact hash checked against initial provenance",
        "build_script_sha256": sha256(Path(__file__)),
        "all_compile_sessions_ended": True,
        "scope": "Independent fixed journal segments; production untouched; no performance claim",
    }
    (HERE / "candidate-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")


if __name__ == "__main__":
    main()
