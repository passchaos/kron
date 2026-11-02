#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("qualification", Path(__file__).resolve().parents[1] / "bench/cpp_reference/qualification.py")
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bench/cpp_reference"))
import analyze


class PairedQualificationTests(unittest.TestCase):
    def rows(self, values):
        return [{"repetition": i, "rate": value} for i, value in enumerate(values)]

    def test_stable_lead_and_regression_follow_ratio_interval(self):
        slow = self.rows([100] * 5)
        fast = self.rows([120, 121, 119, 120, 120])
        self.assertEqual("kron_leads", qualification.paired_metric(fast, slow, "rate")["assessment"])
        self.assertEqual("peer_leads", qualification.paired_metric(slow, fast, "rate")["assessment"])

    def test_latency_direction_and_reordering(self):
        first, other = self.rows([80] * 5), self.rows([100] * 5)
        report = qualification.paired_metric(first, list(reversed(other)), "rate", False)
        self.assertEqual("kron_leads", report["assessment"])
        self.assertEqual(1.25, report["paired_speed_ratio"])

    def test_noisy_inputs_cannot_pass_with_exact_paired_ratios(self):
        peer = self.rows([100, 200, 100, 200, 100])
        kron = self.rows([120, 240, 120, 240, 120])
        report = qualification.paired_metric(kron, peer, "rate")
        self.assertGreater(report["paired_ratio_ci95"][0], 1)
        self.assertEqual("inconclusive", report["assessment"])

    def test_equal_or_fewer_than_five_pairs_do_not_prove_lead(self):
        for first, other in (([100] * 5, [100] * 5), ([120] * 4, [100] * 4)):
            self.assertEqual("inconclusive", qualification.paired_metric(self.rows(first), self.rows(other), "rate")["assessment"])

    def test_duplicate_missing_empty_rounds_rejected(self):
        first = self.rows([100] * 5)
        for other in (first[:-1], first[:-1] + first[:1], []):
            with self.subTest(other=other), self.assertRaises(ValueError):
                qualification.paired_metric(first, other, "rate")

    def test_nonfinite_and_zero_measurements_do_not_prove_lead(self):
        for value in (0, float("inf"), float("nan"), -1):
            self.assertEqual("inconclusive", qualification.paired_metric(self.rows([value] * 5), self.rows([100] * 5), "rate")["assessment"])

    def groups(self):
        def rows(value):
            return [{"repetition": i, "storage": "memory", "metadata": "full",
                     "written_records_per_sec": value, "written_flush_records_per_sec": value,
                     "lifecycle_records_per_sec": value, "init_ns": 100, "shutdown_ns": 100} for i in range(5)]
        return {("kron", "async-memory-inline", 1, "batch"): rows(120),
                ("foundation", "memory", 1, "batch"): rows(100),
                ("foundation_tracing", "memory", 1, "batch"): rows(100)}

    def test_both_frontends_required_and_all_selected_pairs_must_lead(self):
        groups = self.groups()
        self.assertEqual("kron_leads_both_frontends_in_selected_cases", qualification.foundation_comparisons(groups)["written_close_assessment"])
        del groups[("foundation_tracing", "memory", 1, "batch")]
        self.assertEqual("inconclusive", qualification.foundation_comparisons(groups)["written_close_assessment"])
        groups = self.groups()
        groups[("kron", "async-mmap-inline", 1, "batch")] = []
        report = qualification.foundation_comparisons(groups)
        self.assertTrue(report["missing_pairs"])
        self.assertEqual("inconclusive", report["written_close_assessment"])
        groups = self.groups()
        for row in groups[("foundation_tracing", "memory", 1, "batch")]:
            row["written_records_per_sec"] = 140
        self.assertEqual("target_not_met_in_selected_cases", qualification.foundation_comparisons(groups)["written_close_assessment"])

    def test_different_format_cannot_be_qualified(self):
        groups = self.groups()
        groups[("foundation", "memory", 1, "batch")][0]["metadata"] = "native_tracing"
        with self.assertRaises(ValueError):
            qualification.foundation_comparisons(groups)


class CompleteMatrixTests(unittest.TestCase):
    def fixture(self):
        configuration = dict(libraries="foundation,foundation_tracing,kron", producers="1", repeats=5,
                             kron_modes="async", kron_storages="memory", kron_schema="off", metadata="full")
        rows = []
        for library, case in (("foundation", "memory"), ("foundation_tracing", "memory"), ("kron", "async-memory-inline")):
            for phase in ("batch", "sampled"):
                for repetition in range(5):
                    rows.append(dict(library=library, case=case, phase=phase, producers=1, repetition=repetition,
                                     status="ok", metadata="full", storage="memory", events=100, warmup_events=10,
                                     file_records_verified=110, accepted=100, written=100, drop=0, final_pending=0,
                                     init_ns=10, preparation_ns=20, producer_wall_ns=100, flush_ns=10, shutdown_ns=10,
                                     cleanup_ns=10, total_ns=130, lifecycle_ns=160, written_bytes=100,
                                     written_records_per_sec=100 * 1e9 / 130, lifecycle_records_per_sec=110 * 1e9 / 160,
                                     p50_ns=10, p99_ns=20, p999_ns=30, noop_clock_pair_p50_ns=1, noop_clock_pair_p99_ns=2,
                                     has_process_crash_recovery=False))
        return dict(configuration=configuration, child_affinity=[0, 2]), rows

    def report(self, manifest, rows):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "manifest.json").write_text(json.dumps(manifest))
            (path / "results.jsonl").write_text("".join(json.dumps(row) + "\n" for row in rows))
            return analyze.analyze(path)

    def test_selected_single_producer_matrix_renders_without_inventing_p4(self):
        report = self.report(*self.fixture())
        self.assertEqual(30, report["trials"])
        self.assertEqual(6, len(report["groups"]))
        self.assertIn("—", analyze.markdown(report))
        self.assertEqual("inconclusive", report["foundation_qualification"]["written_close_assessment"])

    def test_equal_row_count_cannot_replace_a_requested_group(self):
        manifest, rows = self.fixture()
        for row in rows:
            if row["library"] == "kron" and row["phase"] == "batch":
                row["case"] = "async-mmap-inline"
        with self.assertRaises(AssertionError):
            self.report(manifest, rows)

    def test_duplicate_round_cannot_fill_a_missing_round(self):
        manifest, rows = self.fixture()
        rows[4]["repetition"] = 0
        with self.assertRaises(AssertionError):
            self.report(manifest, rows)

    def test_incomplete_trial_cannot_pass_as_a_complete_matrix(self):
        manifest, rows = self.fixture()
        rows[-1]["status"] = "incomplete_timeout"
        with self.assertRaises(AssertionError):
            self.report(manifest, rows)


if __name__ == "__main__":
    unittest.main()
