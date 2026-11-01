import copy
import importlib.util
import pathlib
import unittest

SPEC = importlib.util.spec_from_file_location("regression", pathlib.Path(__file__).resolve().parents[1] / "bench/regression.py")
REGRESSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REGRESSION)


def capture(values, mode="attached", binary="a"):
    config = {"benchmark": "snapshot", "mode": mode, "events": 10000, "warmup": 1000, "repeats": len(values),
              "cases": [{"phase": "full", "producers": 4}], "affinity": [0, 1], "idle": "sleep",
              "queue_storage": "mmap", "process_crash_recovery": True}
    rows = []
    for index, rate in enumerate(values):
        row = {"status": "ok", "benchmark": "snapshot", "mode": mode, "events": 10000, "warmup": 1000,
               "phase": "full", "producers": 4, "completed": 10000, "accepted": 10000, "written": 10000,
               "drop": 0, "filtered": 0, "final_pending": 0, "runtime_allocations_in_measurement": 0,
               "no_allocations_in_measurement": True, "event_clock": "ZeroClock", "idle": "sleep",
               "queue_slots": 256, "channel_slots": 256, "max_record_bytes": 1024,
               "sink": "counted_complete_json_discard", "steady_state": True, "replace_every_thread0_calls": 0,
               "total_ns": 100, "producer_wall_ns": 80, "flush_ns": 10, "shutdown_ns": 10,
               "completed_per_sec": rate, "p50_ns": 100, "p99_ns": 200}
        row.update({"field_count": 5, "written_bytes": 100000, "queue_storage": "mmap", "process_crash_recovery": True})
        rows.append({"case": config["cases"][0], "repetition": index, "row": row})
    return {"status": "complete", "configuration": config, "rows": rows,
            "metadata": {"binary_sha256": binary, "host_fingerprint": {"kernel": "test"}, "compiler_environment": {"optimize": "ReleaseFast"}}}


class RegressionTests(unittest.TestCase):
    def test_case_and_affinity_parser_preserve_requested_subset(self):
        self.assertEqual(REGRESSION.parse_cases("admission:1,full:16", "snapshot")[1]["producers"], 16)
        self.assertEqual(REGRESSION.affinity("2,4", {2, 4, 6}), [2, 4])
        with self.assertRaises(ValueError): REGRESSION.affinity("0", {2, 4})
        with self.assertRaises(ValueError): REGRESSION.parse_cases("full:3", "snapshot")
        with self.assertRaises(ValueError): REGRESSION.parse_cases("full:4,full:4", "snapshot")

    def test_summary_preserves_quartiles_and_trial_median_ci(self):
        result = REGRESSION.summary([98, 99, 100, 101, 102])
        self.assertEqual(result["median"], 100)
        self.assertEqual((result["q1"], result["q3"]), (99, 101))
        self.assertLessEqual(result["median_bootstrap_ci95"][0], 100)
        self.assertGreaterEqual(result["median_bootstrap_ci95"][1], 100)
        with self.assertRaises(ValueError): REGRESSION.summary([100] * 4)

    def test_stable_regression_is_failure_and_binary_changes_are_allowed(self):
        result = REGRESSION.compare(capture([100] * 5), capture([85] * 5, binary="b"))
        self.assertEqual(result["status"], "regression")
        self.assertFalse(result["same_binary"])

    def test_same_binary_stable_capture_is_tool_selfbaseline(self):
        result = REGRESSION.compare(capture([100] * 5), capture([99, 100, 101, 100, 100]))
        self.assertEqual(result["status"], "within_threshold")
        self.assertTrue(result["same_binary"])

    def test_noisy_trials_are_inconclusive_even_if_median_degrades(self):
        result = REGRESSION.compare(capture([100] * 5), capture([60, 85, 85, 85, 110]))
        self.assertEqual(result["status"], "inconclusive")

    def test_budget_affinity_clock_and_machine_changes_are_rejected(self):
        base = capture([100] * 5)
        for key, value in (("affinity", [0]), ("events", 9999), ("idle", "spin")):
            current = copy.deepcopy(base); current["configuration"][key] = value
            with self.assertRaises(ValueError): REGRESSION.compare(base, current)
        current = copy.deepcopy(base); current["rows"][0]["row"]["event_clock"] = "NativeClock"
        with self.assertRaises(ValueError): REGRESSION.compare(base, current)
        current = copy.deepcopy(base); current["metadata"]["host_fingerprint"]["kernel"] = "changed"
        with self.assertRaises(ValueError): REGRESSION.compare(base, current)

    def test_missing_completion_drop_and_allocation_fail_validation(self):
        base = capture([100] * 5)
        for key, value in (("written", 9999), ("final_pending", 1), ("drop", 1), ("runtime_allocations_in_measurement", 1)):
            candidate = copy.deepcopy(base); candidate["rows"][0]["row"][key] = value
            with self.assertRaises(ValueError): REGRESSION.compare(base, candidate)
        candidate = copy.deepcopy(base); candidate["rows"].pop()
        with self.assertRaises(ValueError): REGRESSION.compare(base, candidate)
        candidate = copy.deepcopy(base); candidate["rows"][0]["repetition"] = 1
        with self.assertRaises(ValueError): REGRESSION.compare(base, candidate)

    def test_changed_queue_budget_and_too_few_trials_are_rejected(self):
        base = capture([100] * 5)
        candidate = copy.deepcopy(base); candidate["rows"][0]["row"]["queue_slots"] = 512
        with self.assertRaises(ValueError): REGRESSION.compare(base, candidate)
        with self.assertRaises(ValueError): REGRESSION.aggregate(capture([100] * 4)["rows"], capture([100] * 4)["configuration"])
        options = REGRESSION.parser().parse_args(["capture", "--binary=test", "--output=test", "--repeats=4"])
        with self.assertRaises(ValueError): REGRESSION.configuration(options)

    def test_zero_latency_resolution_is_inconclusive_without_invalid_json(self):
        base = capture([100] * 5); candidate = copy.deepcopy(base)
        for entry in base["rows"]: entry["row"]["p50_ns"] = 0
        result = REGRESSION.compare(base, candidate)
        self.assertEqual(result["metrics"]["full/p4"]["p50_ns"]["status"], "inconclusive")
        self.assertIsNone(result["metrics"]["full/p4"]["p50_ns"]["relative_change"])

    def test_latency_regression_is_distinct_from_throughput(self):
        base = capture([100] * 5); current = capture([100] * 5)
        for entry in current["rows"]: entry["row"]["p99_ns"] = 240
        result = REGRESSION.compare(base, current)
        self.assertEqual(result["metrics"]["full/p4"]["p99_ns"]["status"], "regression")
        self.assertEqual(result["metrics"]["full/p4"]["throughput"]["status"], "within_threshold")

    def test_explicit_memory_cli_is_recorded_and_passed_to_both_benchmarks(self):
        options = REGRESSION.parser().parse_args(["capture", "--binary=test", "--output=test", "--storage=memory"])
        config = REGRESSION.configuration(options)
        self.assertEqual(config["queue_storage"], "memory")
        self.assertIs(config["process_crash_recovery"], False)
        command = REGRESSION.command("test", config, config["cases"][0], "/tmp/example")
        self.assertIn("--storage=memory", command)
        options = REGRESSION.parser().parse_args(["capture", "--binary=test", "--output=test", "--benchmark=logger", "--storage=memory"])
        config = REGRESSION.configuration(options)
        self.assertEqual(config["queue_storage"], "memory")
        self.assertIs(config["process_crash_recovery"], False)
        self.assertIn("--storage=memory", REGRESSION.command("test", config, config["cases"][0], "/tmp/example"))
        options.storage = "mmap"
        config = REGRESSION.configuration(options)
        self.assertIn("--storage=mmap", REGRESSION.command("test", config, config["cases"][0], "/tmp/example"))

    def test_cross_storage_compare_is_rejected_and_independent_memory_summary_is_valid(self):
        base = capture([100] * 5); memory = copy.deepcopy(base)
        memory["configuration"].update({"queue_storage": "memory", "process_crash_recovery": False})
        for entry in memory["rows"]:
            entry["row"].update({"queue_storage": "memory", "process_crash_recovery": False})
        self.assertEqual(REGRESSION.aggregate(memory["rows"], memory["configuration"])["full/p4"]["throughput"]["median"], 100)
        with self.assertRaises(ValueError): REGRESSION.compare(base, memory)
        self.assertEqual(REGRESSION.compare(memory, copy.deepcopy(memory))["queue_storage"], "memory")
        incomplete = copy.deepcopy(memory)
        incomplete["rows"][0]["row"].pop("process_crash_recovery")
        with self.assertRaises(ValueError): REGRESSION.compare(memory, incomplete)

    def test_reported_storage_and_false_persistence_cannot_masquerade_as_mmap(self):
        base = capture([100] * 5)
        wrong = copy.deepcopy(base); wrong["rows"][0]["row"]["process_crash_recovery"] = False
        with self.assertRaises(ValueError): REGRESSION.compare(base, wrong)
        wrong = copy.deepcopy(base)
        wrong["rows"][0]["row"].update({"queue_storage": "memory", "process_crash_recovery": False})
        with self.assertRaises(ValueError): REGRESSION.compare(base, wrong)
        wrong = copy.deepcopy(base); wrong["configuration"]["process_crash_recovery"] = False
        with self.assertRaises(ValueError): REGRESSION.compare(base, wrong)

    def test_legacy_missing_storage_is_only_mmap_compatible(self):
        legacy = capture([100] * 5); modern = copy.deepcopy(legacy)
        for key in ("queue_storage", "process_crash_recovery"):
            legacy["configuration"].pop(key)
            for entry in legacy["rows"]: entry["row"].pop(key)
        self.assertEqual(REGRESSION.compare(legacy, modern)["queue_storage"], "mmap")
        hidden_memory = copy.deepcopy(legacy)
        hidden_memory["rows"][0]["row"].update({"queue_storage": "memory", "process_crash_recovery": False})
        with self.assertRaises(ValueError): REGRESSION.compare(legacy, hidden_memory)
        legacy_false = copy.deepcopy(legacy)
        legacy_false["rows"][0]["row"]["process_crash_recovery"] = False
        with self.assertRaises(ValueError): REGRESSION.compare(legacy, legacy_false)
        memory_config = copy.deepcopy(modern["configuration"])
        memory_config.update({"queue_storage": "memory", "process_crash_recovery": False})
        with self.assertRaises(ValueError): REGRESSION.aggregate(legacy["rows"], memory_config)

    def test_logger_memory_row_storage_and_mapping_budgets_are_validated(self):
        config = {"benchmark": "logger", "mode": "async", "events": 10000, "warmup": 1000,
                  "clock": "dynamic", "idle": "sleep", "sink": "memory",
                  "queue_storage": "memory", "process_crash_recovery": False}
        case = {"phase": "sampled", "producers": 4}
        row = {"status": "ok", "mode": "async", "phase": "sampled", "producers": 4,
               "events_requested": 10000, "warmup_attempted": 1000, "event_clock": "dynamic",
               "idle_selected": "sleep", "sink": "memory", "format": "json", "fields": 5,
               "payload": "numeric", "filtered_case": False, "overflow": "block", "journal_slots": 256,
               "channel_slots": 256, "max_record_bytes": 16384, "file_buffer_bytes": 65536,
               "queue_depth": 4, "schema_enabled": False, "durable_requested": False,
               "attempted": 10000, "accepted": 10000, "runtime_accepted": 10000, "runtime_written": 10000,
               "sink_written_records": 10000, "filtered": 0, "sampled": 0, "dropped_full": 0,
               "dropped_oversize": 0, "emit_errors": 0, "runtime_write_errors": 0, "rejected_closing": 0,
               "final_pending": 0, "producer_wall_ns": 80, "flush_written_ns": 10, "shutdown_ns": 10,
               "total_ns": 100, "written_records_per_sec": 100, "producer_p50_ns": 1, "producer_p99_ns": 2,
               "queue_storage": "memory", "process_crash_recovery": False, "journal_path": None,
               "journal_mapped_bytes": 0, "journal_allocation_bytes": 0, "queue_allocation_bytes": 4214784}
        self.assertEqual(REGRESSION.validate_row(row, config, case)["throughput"], 100)
        for key, value in (("queue_storage", "mmap"), ("process_crash_recovery", True),
                           ("journal_mapped_bytes", 4214784), ("journal_path", "/tmp/wrong.journal"),
                           ("queue_allocation_bytes", 0), ("queue_allocation_bytes", 4214785)):
            invalid = dict(row); invalid[key] = value
            with self.assertRaises(ValueError): REGRESSION.validate_row(invalid, config, case)


if __name__ == "__main__":
    unittest.main()
