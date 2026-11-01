#!/usr/bin/env python3
"""Seeded ASCII differential gate: Python re.search vs kron Thompson NFA."""
import argparse
import json
import random
import re
import subprocess
import tempfile
from pathlib import Path

MAX_CASES = 4096
DEFAULT_SEED = 0x6B726F6E72656778
INPUT_ALPHABET = "abcxyzABC0129 "


def atom(rng):
    return rng.choice(["a", "b", "c", "x", "0", "9", " ", ".", "[ab]", "[a-c]", "[0-9]", "[^ab]", "[A-Z0-9]", "[a-zA-Z]"])


def ast(rng, depth):
    if depth == 0 or rng.random() < 0.4:
        expression = atom(rng)
    else:
        branch = rng.randrange(4)
        if branch == 0:
            expression = "(" + ast(rng, depth - 1) + "|" + ast(rng, depth - 1) + ")"
        elif branch == 1:
            expression = "(" + ast(rng, depth - 1) + ast(rng, depth - 1) + ")"
        elif branch == 2:
            expression = "(" + ast(rng, depth - 1) + ")"
        else:
            expression = "(" + ast(rng, depth - 1) + "|)"
    if rng.random() < 0.38:
        expression = "(" + expression + ")" + rng.choice(["*", "+", "?"])
    return expression


def cases(seed):
    rng = random.Random(seed)
    # These are valid within the stated grammar. Empty alternatives/groups and
    # nullable nested loops must be checked, never filtered out as inconvenient.
    static = [
        "", "()", "^$", "^()$", "a", ".", "a*", "a+", "a?", "ab*c",
        "ab+c", "ab?c", "a|b", "(a|b)c", "[ab]", "[a-c]+", "[^ab]+",
        "[A-Z0-9]*", "^[a-zA-Z][0-9]?$", "a$", "^a", "^a$", "a|",
        "|a", "(a|)", "(a|b)*", "((a?)*)*", "^((a?)*)*b$", "^(a+)+b$",
        "^(a|aa)*b$", "a^", "$a", "(a)(b)", "(ab|a)b", "[ ]+",
        "^a.*b$", "[^0-9]", "[0-9]?", "(a|ab)+c", "(a*)*", "(a+)?",
        "(()|a)*", "(a||b)", "((ab)?c)*", "^([ab]+|[0-9]*)$",
    ]
    inputs = ["", "a", "b", "ab", "aa", "abc", "0", "9", " ", "ABC9", "aaab", "aaaaaaaaaaaa"]
    corpus = []

    def append(pattern, text):
        # Inputs exclude newline and are at most 12 characters, so CPython's
        # backtracking oracle stays bounded even on the adversarial patterns.
        expected = re.search(pattern, text, flags=re.ASCII) is not None
        corpus.append({"pattern": pattern, "input": text, "expected": expected})

    for pattern in static:
        for text in inputs[:2]:
            append(pattern, text)
    for pattern, text in [
        ("^(a+)+b$", "aaaaaaaaaaaa"),
        ("^(a+)+b$", "aaaaaab"),
        ("^(a|aa)*b$", "aaaaaaaaaaaa"),
        ("^(a|aa)*b$", "aaaaaab"),
        ("^((a?)*)*b$", "aaaaaab"),
        ("^([ab]+|[0-9]*)$", "0129"),
    ]:
        append(pattern, text)
    for _ in range(200):
        pattern = ast(rng, 3)
        if rng.random() < 0.35:
            pattern = "^" + pattern
        if rng.random() < 0.35:
            pattern += "$"
        # 200 patterns × 20 inputs, plus static cases, stays below 4096.
        for index in range(20):
            text = inputs[index] if index < len(inputs) else "".join(rng.choice(INPUT_ALPHABET) for _ in range(rng.randrange(13)))
            append(pattern, text)
    assert len(corpus) <= MAX_CASES
    return corpus


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", "--reader", dest="driver", required=True, type=Path)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED)
    parser.add_argument("--timeout", type=float, default=60)
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("--timeout must be in (0, 60]")
    corpus = cases(args.seed)
    with tempfile.TemporaryDirectory(prefix="kron-regex-differential-") as directory:
        path = Path(directory) / "corpus.json"
        path.write_text(json.dumps(corpus, separators=(",", ":")), encoding="ascii")
        result = subprocess.run([str(args.driver.resolve()), str(path)], timeout=args.timeout, check=False)
        if result.returncode:
            print(f"regex differential seed={args.seed:#x}, cases={len(corpus)} failed", flush=True)
            return result.returncode
    print(f"regex differential seed={args.seed:#x}, patterns=245, cases={len(corpus)} passed", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
