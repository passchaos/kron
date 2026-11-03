#!/usr/bin/env python3
"""Independent actual-binary audit for the consumer-only flat CRC candidate.

Reads the frozen before/candidate reference binaries, disassembles the producer
and general CRC functions, scans every PT_LOAD byte for the 24 canonical CRC
rows, and records the object sizes from DWARF. No compilation, benchmark or
source edit is performed here.
"""
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHADOW = ROOT / ".zig-cache/crc-flat-consumer"
BINARIES = {
    "before-reference": SHADOW / "before-reference",
    "candidate-reference": SHADOW / "candidate-reference",
}
PRODUCER = "core.runtime.Runtime.submitSafeDestination"
GENERAL = "platform.crc32.Crc32.update"
VALIDATION = "journal.format.validationChecksum"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nm(binary):
    out = subprocess.run(["nm", "-S", "-C", str(binary)], capture_output=True, text=True, check=True).stdout
    symbols = {}
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) >= 4 and parts[2] in "tTwW":
            try:
                symbols[" ".join(parts[3:])] = (int(parts[0], 16), int(parts[1], 16))
            except ValueError:
                continue
    return symbols


def disassemble(binary, start, size):
    out = subprocess.run(
        ["objdump", "-d", "--no-show-raw-insn", f"--start-address={hex(start)}",
         f"--stop-address={hex(start + size)}", str(binary)],
        capture_output=True, text=True, check=True).stdout
    instructions = []
    for line in out.splitlines():
        match = re.match(r"\s*([0-9a-f]+):\t(.+)$", line.rstrip("\n"))
        if match:
            instructions.append((int(match.group(1), 16), match.group(2).split("#")[0].strip()))
    return instructions


def normalized(text):
    text = re.sub(r"[0-9a-f]+ <([^>]+)>", lambda match: "<" + match.group(1) + ">", text)
    text = re.sub(r"0x[0-9a-f]{5,}(?=\(|,%|$|\s|,)", "ADDR", text)
    text = re.sub(r"-?0x[0-9a-f]+\(%rip\)", "RIP", text)
    return re.sub(r"\s+", " ", text).strip()


def stream(instructions):
    return [normalized(text) for _, text in instructions]


def rip_data(instructions, path):
    data = Path(path).read_bytes()
    result = []
    for index, (address, text) in enumerate(instructions):
        match = re.search(r"(-?0x[0-9a-f]+)\(%rip\)", text)
        if not match:
            continue
        next_address = instructions[index + 1][0] if index + 1 < len(instructions) else address + 15
        target = next_address + int(match.group(1), 16)
        offset = target - 0x1000000
        result.append({"instruction": index, "target": hex(target), "eight_bytes": data[offset:offset + 8].hex()})
    return result


def metrics(instructions):
    return {
        "instructions": len(instructions),
        "calls": sum(1 for _, text in instructions if text.startswith("call")),
        "pclmul": sum(text.count("pclmul") for _, text in instructions),
        "stackrefs": sum(1 for _, text in instructions if re.search(r"-(0x[0-9a-f]+)?\(%r(sp|bp)\)", text)),
        "frame": next((re.search(r"sub\s+\$0x([0-9a-f]+),%rsp", text).group(1) for _, text in instructions
                       if re.search(r"sub\s+\$0x([0-9a-f]+),%rsp", text)), None),
        "call_targets": sorted(re.sub(r".*<([^>+]+).*", r"\1", text) for _, text in instructions
                               if text.startswith("call")),
    }


def canonical_rows():
    polynomial = 0xEDB88320
    first = []
    for index in range(256):
        value = index
        for _ in range(8):
            value = (value >> 1) ^ (polynomial if value & 1 else 0)
        first.append(value)
    rows = [first]
    for _ in range(1, 24):
        previous = rows[-1]
        rows.append([((previous[index] >> 8) ^ rows[0][previous[index] & 255]) & 0xFFFFFFFF
                     for index in range(256)])
    return [b"".join(value.to_bytes(4, "little") for value in row) for row in rows]


def row_scan(path, patterns):
    data = path.read_bytes()
    found = []
    for pattern in patterns:
        positions = []
        cursor = 0
        while True:
            offset = data.find(pattern, cursor)
            if offset < 0:
                break
            positions.append(hex(offset + 0x1000000))
            cursor = offset + 1
        found.append(positions)
    return found


def object_sizes(binary):
    out = subprocess.run(["readelf", "--debug-dump=info", str(binary)],
                         capture_output=True, text=True, check=True).stdout
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
    symbols = {label: nm(path) for label, path in BINARIES.items()}
    producer = {label: disassemble(path, *symbols[label][PRODUCER]) for label, path in BINARIES.items()}
    general = {label: disassemble(path, *symbols[label][GENERAL]) for label, path in BINARIES.items()}
    producer_streams = {label: stream(value) for label, value in producer.items()}
    general_streams = {label: stream(value) for label, value in general.items()}
    patterns = canonical_rows()
    rows = {label: row_scan(path, patterns) for label, path in BINARIES.items()}
    validation = {}
    for label, path in BINARIES.items():
        entries = {}
        for name, (start, size) in symbols[label].items():
            if name.startswith(VALIDATION):
                instructions = disassemble(path, start, size)
                referenced = sorted({hex(int(match.group(1), 16))
                                     for _, text in instructions
                                     for match in re.finditer(r"0x([0-9a-f]{6,})(?=\(|,%|$|\s|,)", text)
                                     if 0x1060000 <= int(match.group(1), 16) <= 0x1070000})
                entries[name] = {**metrics(instructions), "row_addresses": referenced}
        validation[label] = entries
    record = {
        "review": "independent consumer-only flat CRC actual audit",
        "binary_sha256": {label: sha256(path) for label, path in BINARIES.items()},
        "method": "objdump instruction streams normalized for relocation; exact 1KiB canonical row pattern scan over every file byte; DWARF byte sizes",
        "producer": {
            "symbol": PRODUCER,
            "before": metrics(producer["before-reference"]),
            "candidate": metrics(producer["candidate-reference"]),
            "normalized_streams_equal": producer_streams["before-reference"] == producer_streams["candidate-reference"],
            "rip_data": {label: rip_data(value, BINARIES[label]) for label, value in producer.items()},
            "rip_data_equal": [item["eight_bytes"] for item in rip_data(producer["before-reference"], BINARIES["before-reference"])]
                == [item["eight_bytes"] for item in rip_data(producer["candidate-reference"], BINARIES["candidate-reference"])],
        },
        "general_crc": {
            "symbol": GENERAL,
            "before": metrics(general["before-reference"]),
            "candidate": metrics(general["candidate-reference"]),
            "normalized_streams_equal": general_streams["before-reference"] == general_streams["candidate-reference"],
        },
        "old_slot_checksum": {
            "before_standalone": symbols["before-reference"]["journal.journal.Journal.slotChecksum"],
            "before_metrics": metrics(disassemble(BINARIES["before-reference"],
                                                  *symbols["before-reference"]["journal.journal.Journal.slotChecksum"])),
            "candidate": "not emitted standalone; Reservation.commit inlines it and the producer stream is identical",
        },
        "validation_family": validation,
        "rows": {
            label: {"copies": [len(positions) for positions in rows[label]], "addresses": rows[label]}
            for label in BINARIES
        },
        "rodata_growth": int(subprocess.run(
            ["readelf", "-SW", str(BINARIES["candidate-reference"])],
            capture_output=True, text=True, check=True).stdout.split(".rodata")[1].split()[3], 16)
        - int(subprocess.run(
            ["readelf", "-SW", str(BINARIES["before-reference"])],
            capture_output=True, text=True, check=True).stdout.split(".rodata")[1].split()[3], 16),
        "object_sizes": {label: object_sizes(path) for label, path in BINARIES.items()},
        "limits": "static audit only; no performance or tail qualification inferred",
    }
    (HERE / "actual-review.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({key: record[key] for key in ("producer", "general_crc", "rodata_growth", "object_sizes")}, indent=2))


if __name__ == "__main__":
    main()
