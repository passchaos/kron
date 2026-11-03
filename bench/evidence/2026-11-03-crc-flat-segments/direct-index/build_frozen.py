#!/usr/bin/env python3
"""Freeze the scalar-index representation; preserve the first pointer image."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
INITIAL = ROOT / ".zig-cache/crc-flat-segments"
CANDIDATE = INITIAL / "direct-index"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    initial = json.loads((HERE.parent / "candidate-provenance.json").read_text())
    for name in ("before-reference", "before-bench"):
        if sha256(INITIAL / name) != initial["binary_sha256"][name]:
            raise ValueError("reused baseline artifact changed")
    probe = CANDIDATE / "src/primitive.zig"
    if sha256(probe) != initial["probe_sha256"]:
        raise ValueError("representation probe differs")
    compiler = Path(shutil.which("zig")).resolve(strict=True)
    commands = [
        ("candidate-primitive", [str(compiler), "build-exe", "-O", "ReleaseFast",
                                 f"-Mroot={probe}", f"-femit-bin={CANDIDATE / 'candidate-bench'}"]),
        ("candidate-reference", [str(compiler), "build-exe", "-O", "ReleaseFast", "--dep", "kron",
                                 f"-Mroot={ROOT / 'bench/cpp_reference/kron_reference.zig'}", "-O", "ReleaseFast",
                                 f"-Mkron={CANDIDATE / 'src/root.zig'}",
                                 f"-femit-bin={CANDIDATE / 'candidate-reference'}"]),
    ]
    for name, command in commands:
        if Path(command[-1].split("=", 1)[1]).exists():
            raise ValueError("refusing to overwrite frozen binary")
        (HERE / f"{name}-build-command.json").write_text(json.dumps(command, indent=2) + "\n")
        with (HERE / f"{name}-build.log").open("x") as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        print(f"{name}: build ended", flush=True)
    source = CANDIDATE / "src"
    hashes = {str(p.relative_to(source)): sha256(p) for p in sorted(source.rglob("*"))
              if p.is_file() and p.name != "primitive.zig"}
    before = initial["source_sha256"]["before"]
    pointer = initial["source_sha256"]["candidate"]
    changed = [name for name in sorted(before) if before[name] != hashes[name]]
    representation = [name for name in sorted(pointer) if pointer[name] != hashes[name]]
    if hashes.keys() != before.keys() or changed != ["journal/format.zig", "platform/crc32.zig"]:
        raise ValueError(f"unexpected baseline source difference: {changed}")
    if representation != ["platform/crc32.zig"]:
        raise ValueError(f"unexpected representation difference: {representation}")
    with tarfile.open(HERE / "candidate-source.tar.xz", "x:xz") as archive:
        archive.add(source, arcname="src")
    provenance = {
        "baseline_commit": initial["baseline_commit"],
        "source_sha256": {"before": before, "candidate": hashes},
        "changed_source_files": changed, "representation_difference": representation,
        "source_roots": {"before": str(INITIAL / "before/src"), "candidate": str(source)},
        "binary_sha256": {"before-reference": sha256(INITIAL / "before-reference"),
                          "before-bench": sha256(INITIAL / "before-bench"),
                          "candidate-reference": sha256(CANDIDATE / "candidate-reference"),
                          "candidate-bench": sha256(CANDIDATE / "candidate-bench")},
        "compiler": {"path": str(compiler), "sha256": sha256(compiler),
                     "version": subprocess.run([str(compiler), "version"], check=True, capture_output=True, text=True).stdout.strip()},
        "probe_sha256": sha256(probe), "generated_same_source_probe": "src/primitive.zig",
        "initial_pointer_image_preserved": True, "all_compile_sessions_ended": True,
        "build_script_sha256": sha256(Path(__file__)),
        "scope": "Scalar row indexes only; physical deduplication and performance still require actual gates",
    }
    (HERE / "candidate-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")


if __name__ == "__main__":
    main()
