#!/usr/bin/env python3
"""Reject incomplete init comparisons, workload drift and malformed evidence."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bench"))
import initialization_compare as compare


class InitializationEvidence(unittest.TestCase):
    case = ("spsc", "mmap", 4, True, 8192, "batch")

    def fixture(self):
        row = {"mode": "spsc", "storage": "mmap", "producers": 4, "prepared_schema": True,
               "max_record_bytes": 8192, "phase": "batch", "events": 100, "warmup_events": 10,
               "queue_slots": 256, "consumer_batches_per_queue": 4, "backend_requested": "portable",
               "backend_selected": "portable", "file_buffer_bytes": 65536,
               "event_clock": "std.Io_dynamic_system", "metadata": "full", "optimize": "ReleaseFast",
               "queue_reserved_bytes": ((4096 + 256 * 8256 + 4095) // 4096 * 4096 + 2 * 4160) * 5,
               "init_ns": 100, "preparation_ns": 100, "producer_wall_ns": 100, "flush_ns": 100,
               "shutdown_ns": 100, "cleanup_ns": 100, "total_ns": 400, "lifecycle_ns": 600,
               "written_records_per_sec": 250000000, "p50_ns": None, "p99_ns": None, "p999_ns": None}
        return row

    def test_workload_drift_and_budget_rejected(self):
        compare.check_configuration(self.fixture(), self.case, 100, 10)
        for key, value in (("backend_selected", "linux_uring"), ("queue_slots", 512),
                           ("max_record_bytes", 512), ("queue_reserved_bytes", 1),
                           ("prepared_schema", False), ("event_clock", "zero")):
            row = self.fixture()
            row[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                compare.check_configuration(row, self.case, 100, 10)

    def test_tuple_and_json_list_cases_group_identically(self):
        rows = []
        for side in ("before", "after"):
            for repeat in range(5):
                row = self.fixture()
                row.update(side=side, repetition=repeat, case=list(self.case))
                rows.append(row)
        output = compare.comparison(rows, [self.case], 5)
        self.assertEqual(output["groups"][0]["metrics"]["total_ns"]["median_change_percent"], 0)
        with self.assertRaises(ValueError):
            compare.comparison(rows[:-1], [self.case], 5)
        duplicate = copy.deepcopy(rows)
        duplicate[-1]["repetition"] = 0
        with self.assertRaises(ValueError):
            compare.comparison(duplicate, [self.case], 5)


if __name__ == "__main__":
    unittest.main()
