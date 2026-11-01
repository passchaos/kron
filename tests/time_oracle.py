#!/usr/bin/env python3
"""Validate pure Zig fixed-offset time against Python's independent calendar."""
import argparse
import datetime as dt
import hashlib
import subprocess


def verify(contents):
    timestamps = dates = 0
    epoch = dt.datetime(1970, 1, 1)
    for line in contents.splitlines():
        fields = line.split()
        if fields[0] == "T":
            _, raw, offset, formatted = fields
            ns, minutes = int(raw), int(offset)
            seconds, fraction = divmod(ns, 1_000_000_000)
            civil = epoch + dt.timedelta(seconds=seconds, minutes=minutes)
            suffix = "Z" if minutes == 0 else f"{'-' if minutes < 0 else '+'}{abs(minutes)//60:02}:{abs(minutes)%60:02}"
            expected = f"{civil.year:04}-{civil.month:02}-{civil.day:02}T{civil.hour:02}:{civil.minute:02}:{civil.second:02}.{fraction:09}{suffix}"
            assert formatted == expected, (formatted, expected)
            timestamps += 1
        else:
            assert fields[0] == "D" and len(fields) == 7, line
            _, year, month, day, days, weekday, ordinal = fields
            value = dt.date(int(year), int(month), int(day))
            assert int(days) == (value - epoch.date()).days, line
            assert int(weekday) == value.isoweekday(), line
            assert int(ordinal) == (value - dt.date(value.year, 1, 1)).days + 1, line
            dates += 1
    assert timestamps == 4166 and dates >= 5800, (timestamps, dates)
    return timestamps, dates


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--writer", required=True)
    writer = args.parse_args().writer
    run = subprocess.run([writer], capture_output=True, text=True, timeout=30, check=True)
    timestamps, dates = verify(run.stdout)
    print(f"Independent time oracle passed: {timestamps} nanosecond/offset timestamps, {dates} civil dates; "
          f"sha256={hashlib.sha256(run.stdout.encode()).hexdigest()}")


if __name__ == "__main__":
    main()
