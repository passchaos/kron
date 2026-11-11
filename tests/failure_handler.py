#!/usr/bin/env python3
"""Verify glog-style crash capture in real child processes.

Each mode uses a fresh directory and a real signal or abort:
- record: one report, exit 0, no signal section.
- fatal: one report and SIGABRT, with no duplicate SIGABRT report.
- fatal-log: a `.fatal` event through Logging aborts with the event message.
- segv/abort/term: real signals are captured, mirrored to stderr, and re-raised.

The checks cover report contents, raw stack addresses, the stable symlink, and
the exact terminating signal. They do not establish symbolization quality on
stripped binaries or alternate-stack coverage for threads that never called
`installThreadSignalStack`.
"""

import argparse
import json
import re
import resource
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

PROGRAM = "kron-failure-writer"
HOST = "test-host"
USER = "test-user"
FILE_PATTERN = re.compile(
    rf"^{re.escape(PROGRAM)}\.{re.escape(HOST)}\.{re.escape(USER)}\.log\.FATAL\."
    rf"\d{{8}}-\d{{6}}\.\d+(?:-\d+)?$"
)


def disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run_mode(writer, directory, mode, timeout):
    result = subprocess.run(
        [str(writer), "--directory", str(directory), "--mode", mode],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    return result


def crash_files(directory):
    return sorted(
        path for path in directory.iterdir()
        if path.is_file() and FILE_PATTERN.match(path.name)
    )


def check_report(directory, mode, result):
    files = crash_files(directory)
    assert len(files) == 1, f"{mode}: expected one crash file, found {[p.name for p in files]}"
    path = files[0]
    text = path.read_text(errors="replace")
    stderr = result.stderr.decode(errors="replace")

    assert "PID: " in text and "TID: " in text, text
    assert f"Program: {PROGRAM}" in text, text
    assert f"Host: {HOST}" in text, text
    assert f"User: {USER}" in text, text
    assert "Stack trace:" in text, text
    assert re.search(r"^  #0 0x[0-9a-f]+$", text, re.MULTILINE), text

    link = directory / f"{PROGRAM}.FATAL"
    assert link.is_symlink(), f"{mode}: missing latest symlink"
    assert link.resolve() == path.resolve(), f"{mode}: symlink points elsewhere"

    if mode == "record":
        assert result.returncode == 0, result.returncode
        assert "*** kron failure report ***" in text, text
        assert "Reason: diagnostic" in text, text
        assert "Message: record message" in text, text
        assert "Signal:" not in text, text
        assert "*** kron failure report ***" in stderr, stderr
    elif mode == "fatal":
        assert result.returncode == -signal.SIGABRT, result.returncode
        assert "*** kron failure handler ***" in text, text
        assert "Reason: fatal" in text, text
        assert "Message: intentional fatal message" in text, text
        assert "Signal:" not in text, "fatal report must not duplicate the SIGABRT signal report"
        assert "Symbolized stack trace:" in text, text
        assert "*** kron failure handler ***" in stderr, stderr
    elif mode == "fatal-log":
        assert result.returncode == -signal.SIGABRT, result.returncode
        assert "*** kron failure handler ***" in text, text
        assert "Reason: fatal" in text, text
        assert "Message: fatal log message" in text, text
        assert "Signal:" not in text, "fatal log must not produce a second SIGABRT report"
    else:
        expected = {
            "segv": (signal.SIGSEGV, "SIGSEGV"),
            "abort": (signal.SIGABRT, "SIGABRT"),
            "term": (signal.SIGTERM, "SIGTERM"),
        }[mode]
        assert result.returncode == -expected[0], result.returncode
        assert f"Signal: {expected[1]} (" in text, text
        assert "Signal code: " in text, text
        assert "Fault address: " in text, text
        assert "*** kron failure handler ***" in stderr, stderr
        assert expected[1] in stderr, stderr
        if mode == "segv":
            assert "Fault address: 0x0" in text, text
    return {
        "mode": mode,
        "returncode": result.returncode,
        "file": path.name,
        "bytes": len(text),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--writer", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=20.0)
    args = parser.parse_args()

    results = []
    disable_core_dumps()
    with tempfile.TemporaryDirectory(prefix="kron-failure-") as temporary:
        root = Path(temporary)
        for mode in ("record", "fatal", "fatal-log", "segv", "abort", "term"):
            directory = root / mode
            directory.mkdir()
            result = run_mode(args.writer, directory, mode, args.timeout)
            results.append(check_report(directory, mode, result))
    print(json.dumps({"result": "pass", "cases": results}, sort_keys=True), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 - test harness reports assertion text
        print(f"failure handler verification failed: {error}", file=sys.stderr, flush=True)
        raise
