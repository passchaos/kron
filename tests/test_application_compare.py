import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("application_compare", Path(__file__).resolve().parents[1] / "bench/application_compare.py")
APP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APP)


class ApplicationOracleTests(unittest.TestCase):
    def fixture(self, folder):
        workers, values, warm = APP.reference("compute", 5, 1, 1)
        row = dict(schema_version=1, status="ok", work="compute", mode="shared", storage="memory", operations=5, completed=5,
                   producers=1, warmup_operations=1, log_every=1, sampled=False, runtime_allocations_after_init=0, metadata="full",
                   fields_per_event=5, drop=0, pending=0, producer_ns=1000, flush_ns=100, shutdown_ns=100, cleanup_ns=100,
                   total_ns=1300, runtime_init_ns=100, preparation_ns=100, lifecycle_ns=1500,
                   application_operations_per_sec=5e9/1300, worker_checksums=workers,
                   checksum_sum=sum(x["sum"] for x in workers) & APP.MASK, checksum_xor=workers[0]["xor"],
                   work_table_bytes=2048, work_rounds=64, sample_bytes=0, p50_operation_ns=None, p99_operation_ns=None, p999_operation_ns=None,
                   system_event_clock=True, backend_selected="portable", has_process_crash_recovery=False, queue_slots=256,
                   max_record_bytes=512, file_buffer_bytes=65536, consumer_quanta=4, queue_backing_bytes=151552, journal_backing_bytes=0,
                   accepted=5, written=5, log_attempts=5, warmup_logs=1)
        records = []
        for sequence, (id_, value) in enumerate(list(warm.items()) + list(values.items()), 1):
            records.append(dict(timestamp_ns="1793530000000000000", severity="info", scope="application", message="request complete",
                                session=str(APP.MASK), channel=0, sequence=sequence, route_mask=1, config_generation=1, trace_flags=0,
                                attributes=dict(request_id=id_, result=str(value), producer=0, rounds=64, warmup=id_ in warm)))
        artifact = Path(folder) / "events.jsonl"
        artifact.write_text("".join(json.dumps(record)+"\n" for record in records))
        return row, records, artifact

    def test_complete_work_and_logs_match_independent_state_model(self):
        with tempfile.TemporaryDirectory() as folder:
            row, _, artifact = self.fixture(folder)
            APP.verify(row, artifact)
            self.assertEqual(row["file_records_verified"], 6)
            self.assertEqual(len(row["file_sha256"]), 64)
        # Stateful requests must differ from independent reset-and-hash input.
        _, single, _ = APP.reference("compute", 1, 1, 0)
        _, sequence, _ = APP.reference("compute", 3, 1, 0)
        self.assertEqual(single[0], sequence[0])
        self.assertNotEqual(sequence[1], sequence[2])

    def test_false_application_completion_and_changed_budgets_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            original, _, artifact = self.fixture(folder)
            for key, value in [("completed", 4), ("checksum_sum", 0), ("checksum_xor", 0), ("runtime_allocations_after_init", 1),
                               ("queue_backing_bytes", 1), ("work_table_bytes", 1), ("work_rounds", 1), ("total_ns", 1),
                               ("accepted", 4), ("written", 4), ("has_process_crash_recovery", True)]:
                row = copy.deepcopy(original)
                row[key] = value
                with self.subTest(key=key), self.assertRaises(AssertionError):
                    APP.verify(row, artifact)

    def test_corrupted_result_missing_duplicate_and_partial_records_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            row, records, artifact = self.fixture(folder)
            variants = [records[:-1], records + [records[-1]]]
            for name in ["result", "request_id", "producer", "rounds", "warmup"]:
                changed = copy.deepcopy(records)
                changed[-1]["attributes"][name] = 123
                variants.append(changed)
            wrong_sequence = copy.deepcopy(records)
            wrong_sequence[-1]["sequence"] = 1
            variants.append(wrong_sequence)
            for variant in variants:
                artifact.write_text("".join(json.dumps(record)+"\n" for record in variant))
                with self.assertRaises(AssertionError):
                    APP.verify(copy.deepcopy(row), artifact)
            artifact.write_text("".join(json.dumps(record)+"\n" for record in records).rstrip("\n"))
            with self.assertRaises(AssertionError):
                APP.verify(copy.deepcopy(row), artifact)

    def test_no_logger_baseline_retains_work_and_creates_no_output(self):
        with tempfile.TemporaryDirectory() as folder:
            row, _, artifact = self.fixture(folder)
            artifact.unlink()
            row.update(mode="none", storage="none", backend_selected="none", system_event_clock=False,
                       accepted=0, written=0, log_attempts=0, warmup_logs=0, queue_backing_bytes=0, journal_backing_bytes=0, file_buffer_bytes=0)
            APP.verify(row, artifact)
            artifact.write_bytes(b"")
            with self.assertRaises(AssertionError):
                APP.verify(row, artifact)

    def test_spsc_channel_is_attachment_identity_and_not_application_producer_number(self):
        with tempfile.TemporaryDirectory() as folder:
            row, records, artifact = self.fixture(folder)
            # A producer may attach to any available channel; binding must stay
            # consistent and within the configured attachment pool.
            row.update(mode="spsc", queue_backing_bytes=303104)
            for record in records:
                record["channel"] = 1
            artifact.write_text("".join(json.dumps(record)+"\n" for record in records))
            APP.verify(row, artifact)
            records[-1]["channel"] = 2
            artifact.write_text("".join(json.dumps(record)+"\n" for record in records))
            with self.assertRaises(AssertionError):
                APP.verify(row, artifact)


if __name__ == "__main__":
    unittest.main()
