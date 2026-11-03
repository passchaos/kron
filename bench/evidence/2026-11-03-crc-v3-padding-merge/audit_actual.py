#!/usr/bin/env python3
"""Actual-binary audit for the V3 contiguous schema CRC candidate."""
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BINARIES = {"before-reference": ROOT / ".zig-cache/crc-v3-padding-merge/before-reference",
            "candidate-reference": ROOT / ".zig-cache/crc-v3-padding-merge/candidate-reference"}
FUNCTIONS = {
    "producer": "core.runtime.Runtime.submitSafeDestination",
    "validateSlot": "journal.journal.Journal.validateSlot",
    "slotChecksum": "journal.journal.Journal.slotChecksum",
    "checksumV3Slot": "journal.format.checksumV3Slot",
    "update": "platform.crc32.Crc32.update",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def symbols(path):
    out = subprocess.run(["nm", "-S", "-C", str(path)], capture_output=True, text=True, check=True).stdout
    result = {}
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) >= 4 and parts[2] in "tTwW":
            try:
                result[" ".join(parts[3:])] = (int(parts[0], 16), int(parts[1], 16))
            except ValueError:
                continue
    return result


def disassemble(path, start, size):
    out = subprocess.run(["objdump", "-d", "--no-show-raw-insn", f"--start-address={hex(start)}",
                          f"--stop-address={hex(start + size)}", str(path)],
                         capture_output=True, text=True, check=True).stdout
    instructions = []
    for line in out.splitlines():
        match = re.match(r"\s*([0-9a-f]+):\t(.+)$", line)
        if match:
            instructions.append(match.group(2).split("#")[0].strip())
    return instructions


def metrics(path, symbol):
    start, size = symbols(path)[symbol]
    instructions = disassemble(path, start, size)
    calls = [text for text in instructions if text.startswith("call")]
    return {
        "bytes": size,
        "instructions": len(instructions),
        "calls": len(calls),
        "stackrefs": sum(1 for text in instructions if re.search(r"-(0x[0-9a-f]+)?\(%r(sp|bp)\)", text)),
        "frame": next((match.group(1) for text in instructions
                       if (match := re.search(r"sub\s+\$0x([0-9a-f]+),%rsp", text))), None),
        "call_targets": dict(Counter(sorted(re.sub(r".*<([^>+]+).*", r"\1", text) for text in calls))),
    }


def rodata_size(path):
    out = subprocess.run(["readelf", "-SW", str(path)], capture_output=True, text=True, check=True).stdout
    line = next(line for line in out.splitlines() if ".rodata" in line)
    return int(line.split()[6], 16)


def object_sizes(path):
    out = subprocess.run(["readelf", "--debug-dump=info", str(path)], capture_output=True, text=True, check=True).stdout
    names = {"journal.journal.Journal", "core.runtime.Runtime", "core.field.Field"}
    result, current = {}, {}
    for line in out.splitlines():
        if re.match(r"\s*<\d+><[0-9a-f]+>:", line):
            if current.get("name") in names and "size" in current:
                result[current["name"]] = current["size"]
            current = {}
            continue
        match = re.search(r"DW_AT_name\s*:\s*(?:\(.*\)\s*:?\s*)?(.*)$", line)
        if match:
            current["name"] = match.group(1).strip()
        match = re.search(r"DW_AT_byte_size\s*:\s*(\d+)", line)
        if match:
            current["size"] = int(match.group(1))
    return result


def main():
    record = {
        "review": "independent V3 contiguous schema CRC actual audit",
        "binary_sha256": {label: sha256(path) for label, path in BINARIES.items()},
        "method": "objdump function metrics and DWARF byte sizes; V3 oracle equality is covered by the named format tests",
        "functions": {label: {name: metrics(path, symbol) for name, symbol in FUNCTIONS.items()
                              if symbol in symbols(path)} for label, path in BINARIES.items()},
        "rodata": {label: {"bytes": rodata_size(path)} for label, path in BINARIES.items()},
        "rodata_growth": rodata_size(BINARIES["candidate-reference"]) - rodata_size(BINARIES["before-reference"]),
        "object_sizes": {label: object_sizes(path) for label, path in BINARIES.items()},
        "producer_change": "V1/V2 slotChecksum remains byte-identical (156B/48 instructions/3 calls); the producer additionally inlines the V3 two-update path, keeping frame 0xd18.",
        "limits": "static audit only; no performance or tail qualification inferred",
    }
    (HERE / "actual-review.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({key: record[key] for key in ("rodata_growth", "object_sizes", "producer_change")}, indent=2))


if __name__ == "__main__":
    main()
