#!/usr/bin/env python3
"""Check that full-workflow comparisons cannot pass truncated or weaker output."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("cpp_reference", Path(__file__).resolve().parents[1] / "bench/cpp_reference/run.py")
driver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(driver)


class VerificationTests(unittest.TestCase):
    def fixture(self, folder):
        event = {"timestamp_ns": "1793490000000000000", "severity": "info", "scope": "reference", "message": "event",
                 "session": "18446744073709551615", "channel": 0, "sequence": 1, "route_mask": 1,
                 "config_generation": 1, "trace_flags": 0, "attributes": {f"field{i}": i for i in range(5)}}
        data = (json.dumps(event, separators=(",", ":")) + "\n").encode()
        artifact = Path(folder) / "events.jsonl"
        artifact.write_bytes(data)
        row = {"schema_version": 2, "library": "spdlog", "status": "ok", "events": 1, "warmup_events": 0,
               "accepted": 1, "written": 1, "drop": 0, "final_pending": 0, "phase": "batch", "metadata": "full",
               "total_ns": 1000, "producer_wall_ns": 700, "flush_ns": 100, "shutdown_ns": 100, "cleanup_ns": 100,
               "init_ns": 200, "preparation_ns": 300, "lifecycle_ns": 1500, "written_records_per_sec": 1000000,
               "sample_count": 0, "p50_ns": None, "p99_ns": None, "p999_ns": None,
               "written_bytes": len(data), "artifact_bytes": len(data), "queue_policy": "block", "file_buffer_bytes": 65536}
        return event, artifact, row

    def test_exact_metadata_and_full_lifecycle_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            _, artifact, row = self.fixture(folder)
            driver.verify(row, artifact, 1, 0)
            self.assertEqual(row["file_records_verified"], 1)

    def test_missing_cleanup_or_wrong_throughput_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            _, artifact, row = self.fixture(folder)
            for key, value in (("cleanup_ns", 0), ("lifecycle_ns", 1400), ("written_records_per_sec", 2000000), ("final_pending", 1)):
                changed = copy.deepcopy(row)
                changed[key] = value
                with self.subTest(key=key), self.assertRaises(AssertionError):
                    driver.verify(changed, artifact, 1, 0)

    def test_weaker_metadata_corrupt_field_and_partial_tail_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            event, artifact, row = self.fixture(folder)
            for change in ("missing", "field", "identity", "timestamp"):
                changed = copy.deepcopy(event)
                if change == "missing":
                    del changed["scope"]
                elif change == "field":
                    changed["attributes"]["field4"] = 99
                elif change == "identity":
                    changed["sequence"] = 0
                else:
                    changed["timestamp_ns"] = 1793490000000000000
                data = (json.dumps(changed, separators=(",", ":")) + "\n").encode()
                artifact.write_bytes(data)
                updated = dict(row, artifact_bytes=len(data), written_bytes=len(data))
                with self.subTest(change=change), self.assertRaises(AssertionError):
                    driver.verify(updated, artifact, 1, 0)
            artifact.write_bytes(b'{"partial":')
            updated = dict(row, artifact_bytes=11, written_bytes=11)
            with self.assertRaises(AssertionError):
                driver.verify(updated, artifact, 1, 0)

    def test_memory_queue_cannot_claim_process_crash_recovery(self):
        with tempfile.TemporaryDirectory() as folder:
            _, artifact, row = self.fixture(folder)
            row.update(library="kron", storage="memory", has_process_crash_recovery=True, journal_reserved_bytes=0, queue_reserved_bytes=151552)
            with self.assertRaises(AssertionError):
                driver.verify(row, artifact, 1, 0)

    def test_foundation_tracing_requires_real_backend_completion(self):
        with tempfile.TemporaryDirectory() as folder:
            _, artifact, row = self.fixture(folder)
            row.update(library="foundation_tracing", storage="memory", has_process_crash_recovery=False,
                       foundation_submitted_records=1, foundation_written_records=1, foundation_written_bytes=row["artifact_bytes"])
            driver.verify(row, artifact, 1, 0)
            for key in ("foundation_submitted_records", "foundation_written_records", "foundation_written_bytes"):
                changed = dict(row, **{key: 0})
                with self.subTest(key=key), self.assertRaises(AssertionError):
                    driver.verify(changed, artifact, 1, 0)

    def test_native_tracing_control_rejects_missing_duplicate_and_truncated_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            _, artifact, base = self.fixture(folder)
            good = b"2026-11-02T00:00:00.000000Z  INFO ThreadId(2) benchmark.rs:10: event field0=0 field1=1 field2=2 field3=3 field4=4\n"
            for data, passing in [(good, True), (good.replace(b"field4=4", b""), False),
                                  (good.replace(b"field4=4", b"field4=99"), False),
                                  (good.replace(b"field4=4", b"field3=3"), False), (good[:-1], False)]:
                artifact.write_bytes(data)
                row = dict(base, library="foundation_tracing", storage="memory", metadata="native_tracing", has_process_crash_recovery=False,
                           artifact_bytes=len(data), written_bytes=len(data), foundation_written_bytes=len(data), foundation_submitted_records=1, foundation_written_records=1)
                if passing:
                    driver.verify(row, artifact, 1, 0)
                else:
                    with self.subTest(data=data), self.assertRaises(AssertionError):
                        driver.verify(row, artifact, 1, 0)


if __name__ == "__main__":
    unittest.main()
