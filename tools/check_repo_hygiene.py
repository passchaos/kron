#!/usr/bin/env python3
"""Guard the repository against generated artifacts and oversized files.

The checks are intentionally cheap and Git-index based, so they work in CI and
before a commit without scanning ignored build directories.
"""
import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GENERATED_DIRS = (".zig-cache/", "zig-out/", "__pycache__/", "zig-pkg/")
GENERATED_SUFFIXES = (".pyc",)
REFERENCE_BINARIES = (
    "bench/evidence/*/reference-foundation",
    "bench/evidence/*/reference-foundation_tracing",
    "bench/evidence/*/reference-kron",
)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-bytes", type=int, default=8 * 1024 * 1024, help="maximum tracked file size")
    args = parser.parse_args()

    failures: list[str] = []
    tracked = [line for line in git("ls-files", "-z").split("\0") if line]
    ignored_tracked = [line for line in git("ls-files", "-ci", "--exclude-standard").splitlines() if line]

    if ignored_tracked:
        failures.append(f"{len(ignored_tracked)} tracked file(s) match .gitignore")
        for path in ignored_tracked[:10]:
            failures.append(f"  {path}")

    generated = [path for path in tracked if any(part in path for part in GENERATED_DIRS) or path.endswith(GENERATED_SUFFIXES)]
    if generated:
        failures.append(f"{len(generated)} tracked generated file(s)")
        for path in generated[:10]:
            failures.append(f"  {path}")

    oversized = []
    for path in tracked:
        full = os.path.join(ROOT, path)
        if os.path.isfile(full) and os.path.getsize(full) > args.max_bytes:
            oversized.append((os.path.getsize(full), path))
    if oversized:
        failures.append(f"{len(oversized)} tracked file(s) exceed {args.max_bytes} bytes")
        for size, path in sorted(oversized, reverse=True)[:10]:
            failures.append(f"  {size:>10} {path}")

    reference_binaries = [path for path in tracked if os.path.basename(path) in REFERENCE_BINARIES]
    if reference_binaries:
        failures.append(f"{len(reference_binaries)} tracked benchmark reference binary/binaries")
        for path in reference_binaries[:10]:
            failures.append(f"  {path}")

    if failures:
        print("repository hygiene check failed:", file=sys.stderr)
        for line in failures:
            print(line, file=sys.stderr)
        return 1

    largest = max(((os.path.getsize(os.path.join(ROOT, path)), path) for path in tracked if os.path.isfile(os.path.join(ROOT, path))), default=(0, ""))
    print(f"repository hygiene ok: {len(tracked)} tracked files, largest {largest[1]} ({largest[0]} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
