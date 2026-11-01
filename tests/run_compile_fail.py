#!/usr/bin/env python3
"""Verify producer type errors against the real public module."""
import argparse
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--zig", default="zig")
options = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
cases = {
    "bare_pointer.zig": "kron cannot capture",
    "array_by_value.zig": "kron cannot capture",
    "duplicate_tuple.zig": "DuplicateKey",
    "format_wrong_type.zig": "ArgumentTypeMismatch",
    "format_missing_argument.zig": "TooFewArguments",
    "format_custom_formatter.zig": "explicit preencoded",
    "configuration_snapshot_access.zig": "no field named 'configuration'",
    "runtime_filter_access.zig": "no field named 'filter'",
    "adapter_unsupported_member.zig": "cannot capture selected member",
    "adapter_byte_array.zig": "cannot capture selected member",
    "adapter_implicit_nested.zig": "cannot capture selected member",
    "adapter_duplicate_selection.zig": "duplicate selected member",
    "adapter_missing_member.zig": "has no selected member",
    "adapter_input_by_value.zig": "input must be a pointer",
    "adapter_tuple.zig": "requires named struct members",
    "adapter_selection_budget.zig": "64 selected-field budget",
    "adapter_duplicate_key.zig": "duplicate output key",
}
for filename, diagnostic in cases.items():
    source = root / "tests" / "compile_fail" / filename
    result = subprocess.run(
        [options.zig, "build-exe", "-fno-emit-bin", "--dep", "kron",
         f"-Mroot={source}", f"-Mkron={root / 'src/root.zig'}"],
        cwd=root, capture_output=True, text=True, timeout=60,
    )
    if result.returncode == 0 or diagnostic not in result.stderr:
        raise SystemExit(f"{filename}: missing expected rejection {diagnostic!r}\n{result.stderr}")
    print(f"PASS {filename}: {diagnostic}")
