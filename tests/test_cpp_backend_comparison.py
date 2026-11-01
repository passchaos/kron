#!/usr/bin/env python3
"""Reject backend fallback, incomplete output and drift in the full workflow."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bench/cpp_reference"))
import compare_backends


class BackendVerification(unittest.TestCase):
    def fixture(self, folder):
        event = {"timestamp_ns": "1793490000000000000", "severity": "info", "scope": "reference", "message": "event",
                 "session": "18446744073709551615", "channel": 0, "sequence": 1, "route_mask": 1,
                 "config_generation": 1, "trace_flags": 0, "attributes": {f"field{i}": i for i in range(5)}}
        payload = (json.dumps(event, separators=(",", ":")) + "\n").encode()
        artifact = Path(folder) / "events.jsonl"
        artifact.write_bytes(payload)
        row = {"schema_version": 2, "library": "kron", "status": "ok", "events": 1, "warmup_events": 0,
               "accepted": 1, "written": 1, "drop": 0, "final_pending": 0, "phase": "batch", "metadata": "full",
               "total_ns": 1000, "producer_wall_ns": 700, "flush_ns": 100, "shutdown_ns": 100, "cleanup_ns": 100,
               "init_ns": 200, "preparation_ns": 300, "lifecycle_ns": 1500, "written_records_per_sec": 1000000,
               "sample_count": 0, "p50_ns": None, "p99_ns": None, "p999_ns": None,
               "written_bytes": len(payload), "artifact_bytes": len(payload), "queue_policy": "block", "file_buffer_bytes": 65536,
               "mode": "async", "storage": "memory", "producers": 1, "has_process_crash_recovery": False,
               "journal_reserved_bytes": 0, "queue_reserved_bytes": 151552, "consumer_batches_per_queue": 4,
               "queue_slots": 256, "max_record_bytes": 512,
               "backend_selected": "linux_uring", "backend_requested": "linux_uring"}
        return artifact, row

    def verify(self, row, artifact):
        compare_backends.verify_trial(row, artifact, 1, 0, "linux_uring", "async", "memory", 1, "batch")

    def test_valid_file_and_actual_backend(self):
        with tempfile.TemporaryDirectory() as folder:
            artifact, row = self.fixture(folder)
            self.verify(row, artifact)
            self.assertEqual(row["file_records_verified"], 1)

    def test_reject_fallback_and_workload_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            artifact, row = self.fixture(folder)
            for key, value in (("backend_selected", "portable"), ("backend_requested", "auto"),
                               ("consumer_batches_per_queue", 1), ("mode", "spsc"), ("producers", 4),
                               ("queue_slots", 257), ("max_record_bytes", 1024)):
                changed = copy.deepcopy(row)
                changed[key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    self.verify(changed, artifact)

    def test_reject_missing_written_and_incomplete_output(self):
        with tempfile.TemporaryDirectory() as folder:
            artifact, row = self.fixture(folder)
            changed = dict(row, written=0)
            with self.assertRaises(AssertionError):
                self.verify(changed, artifact)
            payload = artifact.read_bytes()[:-1]
            artifact.write_bytes(payload)
            changed = dict(row, written_bytes=len(payload), artifact_bytes=len(payload))
            with self.assertRaises(AssertionError):
                self.verify(changed, artifact)


if __name__ == "__main__":
    unittest.main()
