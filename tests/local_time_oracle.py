#!/usr/bin/env python3
"""Verify system local rendering against Python zoneinfo in isolated processes."""
import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
from zoneinfo import ZoneInfo


def invoke(binary, directory, zone, mode):
    environment = dict(os.environ, TZ=zone)
    environment.pop("TZDIR", None)
    return subprocess.run([binary, mode], cwd=directory, env=environment,
                          capture_output=True, text=True, timeout=20)


def verify(contents, zone):
    location = ZoneInfo(zone or "UTC")
    epoch = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
    events = [json.loads(line) for line in contents.splitlines()]
    assert len(events) == 12, len(events)
    for index, event in enumerate(events):
        ns = int(event["timestamp_ns"])
        seconds, fraction = divmod(ns, 1_000_000_000)
        local = (epoch + dt.timedelta(seconds=seconds)).astimezone(location)
        minutes = int(local.utcoffset().total_seconds()) // 60
        suffix = "Z" if minutes == 0 else f"{'-' if minutes < 0 else '+'}{abs(minutes)//60:02}:{abs(minutes)%60:02}"
        expected = local.strftime("%Y-%m-%dT%H:%M:%S") + f".{fraction:09}" + suffix
        assert event["timestamp"] == expected, (zone, event, expected)
        assert event["attributes"]["id"] == index
    return len(events)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--writer", required=True)
    binary = str(pathlib.Path(parser.parse_args().writer).resolve())
    total = 0
    zones = ("", "UTC", "Asia/Shanghai", "America/New_York", "Australia/Lord_Howe", "Pacific/Chatham")
    modes = ("sync", "memory", "mmap", "spsc-memory", "spsc-mmap")
    for zone in zones:
        for mode in modes:
            with tempfile.TemporaryDirectory(prefix="kron-local-oracle-") as folder:
                run = invoke(binary, folder, zone, mode)
                assert run.returncode == 0, (zone, mode, run.stderr)
                total += verify(run.stdout, zone)
    with tempfile.TemporaryDirectory(prefix="kron-local-recovery-") as folder:
        failed = invoke(binary, folder, "America/New_York", "fail")
        assert failed.returncode == 0, failed.stderr
        journal = pathlib.Path(folder) / "oracle.journal"
        original = hashlib.sha256(journal.read_bytes()).hexdigest()
        rejected = invoke(binary, folder, "UTC", "recover")
        assert rejected.returncode != 0 and "RecoveryRouteMismatch" in rejected.stderr, rejected.stderr
        assert hashlib.sha256(journal.read_bytes()).hexdigest() == original
        restored = invoke(binary, folder, "America/New_York", "recover")
        assert restored.returncode == 0, restored.stderr
        total += verify(restored.stdout, "America/New_York")
    with tempfile.TemporaryDirectory(prefix="kron-local-history-") as folder:
        historic = invoke(binary, folder, "Europe/Paris", "historic")
        assert historic.returncode != 0 and "NonMinuteLocalOffset" in historic.stderr, historic.stderr
    print(f"System local oracle: {len(zones)} zones × {len(modes)} modes, {total} complete timestamps; "
          "DST/half-hour/quarter-hour/rollback/future, changed-zone recovery rejection and historical offset checked")


if __name__ == "__main__":
    main()
