#!/usr/bin/env python3
"""Seeded byte-regex differential gate against Python's independent engine."""
import argparse
import gzip
import hashlib
import json
import random
import re
import subprocess
import tempfile
import warnings
from pathlib import Path

MAX_CASES = 32768
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


def strict_end(pattern):
    """kron's $ means absolute end, including inputs ending in newline.

    Python's $ also accepts a position before one final newline. Translate
    only unescaped anchors outside classes to Python's absolute-end anchor.
    Matching, classes, repetition and search still use Python's own engine.
    """
    result = bytearray()
    in_class = False
    first = False
    may_negate = False
    index = 0
    while index < len(pattern):
        byte = pattern[index]
        if byte == ord("\\"):
            result.extend(pattern[index:index + 2])
            index += 2
            first = False
            may_negate = False
            continue
        if not in_class and byte == ord("["):
            in_class, first, may_negate = True, True, True
        elif in_class:
            if byte == ord("]") and not first:
                in_class = False
            elif byte == ord("^") and may_negate:
                may_negate = False
                result.append(byte)
                index += 1
                continue
            first = False
            may_negate = False
        elif byte == ord("$"):
            result.extend(b"\\Z")
            index += 1
            continue
        result.append(byte)
        index += 1
    return bytes(result)


def byte_cases(seed):
    corpus = []

    def append(pattern, text, *, compile_error=None, match_error=None):
        case = {"pattern_hex": pattern.hex(), "input_hex": text.hex()}
        if compile_error:
            case["compile_error"] = compile_error
        elif match_error:
            case["match_error"] = match_error
        else:
            # [ [] is a supported literal-[ class today; Python warns about
            # possible future set syntax. No unsupported grammar is generated.
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", FutureWarning)
                case["expected"] = re.search(strict_end(pattern), text) is not None
        corpus.append(case)

    # Preserve every original exact comparison before extending the grammar.
    for case in cases(seed):
        append(case["pattern"].encode("ascii"), case["input"].encode("ascii"))

    patterns = [
        b"", b"()", b"^$", b"$", b"^a$", b"a$", b".$", b"^.$",
        b"a\\n$", b"a\\r?\\n$", b"\\n", b"\\r", b"\\t", b"\\f",
        b"\\v", b"\\a", b"[\\n\\r\\t]", b"[^\\n]", b"[\\x00-\\xFF]",
        b"^.*$", b"^[^\\n]*$", b"^((a?)*)*b$", b"(a|aa)*b",
        b"\\.", b"\\*", b"\\+", b"\\?", b"\\^", b"\\$", b"\\|",
        b"\\(", b"\\)", b"\\[", b"\\]", b"\\{", b"\\}", b"\\\\",
        b"[-a]", b"[a-]", b"[]a]", b"[^]a]", b"[]]", b"[^]]",
        b"[\\]-a]", b"[a\\-c]", b"[\\\\]", b"[\\^$]", b"[[]",
        b"^\\x00$", b"^\\xff$", b"[\\x7f-\\xff]+", b"\x00", b"\xff",
        b"^\xc3\xa9$", b"^..$", b"[\x00-\xff]", b"[^\x00-\xff]",
        b"\\$[a$]$", b"[\\x24]$", b"[$]$", b"[]$]$", b"(^)*a", b"($)+",
        b"[^^]$", b"[\\]^$]$",
    ]
    inputs = [
        b"", b"a", b"b", b"aa", b"ab", b"a\n", b"\n", b"\n\n",
        b"a\n\n", b"a\r\n", b"a\rb", b"a\tb", b"a\nb", b"\x00",
        b"\xff", b"\x7f", b"\x80", b"\x0c", b"\x0b", b"\x07",
        b"\\", b"[]", b"]a", b"^$", b"$a$", b"\xc3\xa9", b"aaaaab",
    ]
    for pattern in patterns:
        for text in inputs:
            append(pattern, text)

    # Every possible byte participates in literal, dot and class matching.
    for byte in range(256):
        escaped = f"\\x{byte:02x}".encode("ascii")
        for pattern in (escaped, b"[" + escaped + b"]", b"[^" + escaped + b"]", b"."):
            append(pattern, bytes([byte]))
            append(pattern, bytes([byte ^ 0xff]))

    rng = random.Random(seed ^ 0x62797465)
    atoms = [b"a", b"b", b"0", b".", b"[]a]", b"[^]a]", b"[a-c]",
             b"[-a]", b"[a-]", b"[\\n\\t]", b"[^\\n]", b"[\\x00-\\xff]",
             b"\\x00", b"\\xff", b"\\n", b"\\r", b"\\t", b"\\f",
             b"\\\\", b"\\[", b"\\]", b"\\$", b"\\."]

    def expression(depth):
        if depth == 0 or rng.random() < 0.4:
            value = rng.choice(atoms)
        else:
            left = expression(depth - 1)
            branch = rng.randrange(3)
            if branch == 0:
                value = b"(" + left + b"|" + expression(depth - 1) + b")"
            elif branch == 1:
                value = b"(" + left + expression(depth - 1) + b")"
            else:
                value = b"(" + left + b"|)"
        if rng.random() < 0.35:
            value = b"(" + value + b")" + rng.choice([b"*", b"+", b"?"])
        return value

    alphabet = b"ab0]\n\r\t\x00\x7f\x80\xff.$\\"
    for _ in range(1536):
        pattern = expression(3)
        if rng.random() < 0.35:
            pattern = b"^" + pattern
        if rng.random() < 0.35:
            pattern += b"$"
        for index in range(8):
            # Six-byte random inputs bound the independent backtracking oracle;
            # long pathological inputs use direct fixed NFA resource tests.
            text = inputs[index] if index < 3 else bytes(rng.choice(alphabet) for _ in range(rng.randrange(7)))
            append(pattern, text)

    invalid = [b"\\", b"[", b"[]", b"[^]", b"[a-", b"[z-a]", b"[a-\\x00]",
               b"\\x", b"\\x0", b"\\xgg", b"\\x+1", b"\\x_1", b"(", b")", b"*a", b"a**",
               b"a+?", b"a?+", b"^*", b"$+", b"a$?"]
    unsupported = [b"\\d", b"\\D", b"\\w", b"\\W", b"\\s", b"\\S",
                   b"\\b", b"\\B", b"\\A", b"\\Z", b"\\z", b"\\u1234",
                   b"\\U00000061", b"\\N{name}", b"\\q", b"(a)\\1",
                   b"\\0", b"[\\D]", b"a{2}", b"(?=a)", b"(?:a)", b"(?i)a"]
    for pattern in invalid:
        append(pattern, b"", compile_error="InvalidRegex")
    for pattern in unsupported:
        append(pattern, b"", compile_error="UnsupportedRegex")
    append(b"a" * 128, b"", compile_error="TooManyRegexStates")
    append(b"(" * 33 + b"a" + b")" * 33, b"", compile_error="RegexNestingTooDeep")
    append(b"^a+$", b"a" * 8192)
    append(b"^a+$", b"a" * 8193, match_error="InputTooLong")
    assert 0 < len(corpus) <= MAX_CASES
    return corpus


def negative_checks(driver, path, timeout):
    checks = [
        ("wrong match", [{"pattern_hex": "61", "input_hex": "61", "expected": False}], "RegexDifferentialMismatch"),
        ("wrong compile error", [{"pattern_hex": "5c44", "input_hex": "", "compile_error": "InvalidRegex"}], "RegexDifferentialMismatch"),
        ("unexpected compile success", [{"pattern_hex": "61", "input_hex": "", "compile_error": "InvalidRegex"}], "RegexDifferentialMismatch"),
        ("missing match error", [{"pattern_hex": "61", "input_hex": "61", "match_error": "InputTooLong"}], "RegexDifferentialMismatch"),
        ("malformed hex", [{"pattern_hex": "gg", "input_hex": "", "expected": False}], "InvalidCorpus"),
        ("missing expectation", [{"pattern_hex": "61", "input_hex": "61"}], "InvalidCorpus"),
        ("ambiguous expectation", [{"pattern_hex": "61", "input_hex": "61", "expected": True, "compile_error": "InvalidRegex"}], "InvalidCorpus"),
        ("empty corpus", [], "InvalidCaseCount"),
    ]
    reports = []
    for name, corpus, expected_error in checks:
        path.write_text(json.dumps(corpus), encoding="ascii")
        result = subprocess.run([str(driver.resolve()), str(path)], timeout=timeout,
                                check=False, capture_output=True, text=True)
        if result.returncode == 0 or expected_error not in result.stderr:
            raise RuntimeError(f"driver negative check {name!r} did not reject with {expected_error}: {result.stderr}")
        reports.append({"name": name, "returncode": result.returncode, "error": expected_error})
    return reports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", "--reader", dest="driver", required=True, type=Path)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", type=Path, help="retain the exact hex corpus and result summary")
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("--timeout must be in (0, 60]")
    corpus = byte_cases(args.seed)
    with tempfile.TemporaryDirectory(prefix="kron-regex-differential-") as directory:
        path = Path(directory) / "corpus.json"
        data = json.dumps(corpus, separators=(",", ":"))
        path.write_text(data, encoding="ascii")
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            (args.output / "corpus.json.gz").write_bytes(gzip.compress(data.encode("ascii"), mtime=0))
        result = subprocess.run([str(args.driver.resolve()), str(path)], timeout=args.timeout, check=False)
        negatives = negative_checks(args.driver, path, args.timeout) if result.returncode == 0 else []
        summary = {"seed": args.seed, "cases": len(corpus),
                   "corpus_sha256": hashlib.sha256(data.encode("ascii")).hexdigest(),
                   "patterns": len({case["pattern_hex"] for case in corpus}),
                   "comparisons": sum("expected" in case for case in corpus),
                   "compile_errors": sum("compile_error" in case for case in corpus),
                   "match_errors": sum("match_error" in case for case in corpus),
                   "driver_returncode": result.returncode,
                   "negative_checks": negatives,
                   "oracle": "Python re.search on bytes; unescaped $ maps to absolute-end \\Z"}
        if args.output:
            (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="ascii")
        if result.returncode:
            print(f"regex differential seed={args.seed:#x}, cases={len(corpus)} failed", flush=True)
            return result.returncode
    print(f"regex differential seed={args.seed:#x}, patterns={summary['patterns']}, "
          f"comparisons={summary['comparisons']}, compile_errors={summary['compile_errors']}, "
          f"match_errors={summary['match_errors']}, negative_checks={len(negatives)} passed", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
