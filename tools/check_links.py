#!/usr/bin/env python3
"""Check relative links in tracked Markdown files.

HTTP(S), mailto and anchor-only links are ignored. Fenced code blocks are
removed first so command examples do not produce false positives. Generated
directories such as zig-out and zig-pkg are excluded by Git's ignore rules.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"\]\(([^)\s]+)\)")


def markdown_files() -> list[str]:
    output = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.md"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [line for line in output.splitlines() if line]


def without_fences(text: str) -> str:
    lines = []
    fenced = False
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fenced = not fenced
            continue
        if not fenced:
            lines.append(line)
    return "\n".join(lines)


def main() -> int:
    broken = []
    for relative in markdown_files():
        path = os.path.join(ROOT, relative)
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = without_fences(handle.read())
        for match in LINK.finditer(text):
            target = match.group(1)
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0]
            if not target:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(relative), target))
            if not os.path.exists(os.path.join(ROOT, resolved)):
                broken.append((relative, target))
    if broken:
        print("broken Markdown links:", file=sys.stderr)
        for source, target in broken:
            print(f"  {source}: {target}", file=sys.stderr)
        return 1
    print(f"Markdown links ok ({len(markdown_files())} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
