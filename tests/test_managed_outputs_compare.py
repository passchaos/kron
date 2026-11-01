#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('managed_compare', Path(__file__).resolve().parents[1] / 'bench/managed_outputs_compare.py')
compare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare)

class OutputOracleTests(unittest.TestCase):
    def records(self):
        return [{'attributes': {'id': i, 'payload': 'constant-value'}, 'message': 'managed output', 'scope': 'managed.bench', 'severity': 'info', 'sequence': sequence, 'session': '1', 'route_mask': 1, 'config_generation': 1} for sequence, i in enumerate(list(range(1000)) + list(range(1000)), 1)]

    def check(self, records):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'events.jsonl'
            path.write_text(''.join(json.dumps(record) + '\n' for record in records))
            return compare.validate_output(path, 1000)

    def test_complete_output(self):
        self.assertEqual(2000, self.check(self.records()))

    def test_missing_and_extra_record(self):
        records = self.records()
        for changed in (records[:-1], records + records[-1:]):
            with self.subTest(length=len(changed)), self.assertRaises(ValueError):
                self.check(changed)

    def test_duplicate_record(self):
        records = self.records()
        records[1700] = records[1699]
        with self.assertRaises(ValueError):
            self.check(records)

    def test_wrong_payload(self):
        records = self.records()
        records[1700]['attributes']['payload'] = 'changed'
        with self.assertRaises(ValueError):
            self.check(records)

    def test_wrong_level(self):
        records = self.records()
        records[1700]['severity'] = 'debug'
        with self.assertRaises(ValueError):
            self.check(records)

    def test_sequence_and_admission_metadata(self):
        for key, value in [('sequence', 1700), ('route_mask', 0), ('config_generation', 0), ('session', '2')]:
            records = self.records()
            records[1700][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.check(records)

    def test_truncated_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'events.jsonl'
            path.write_text('{"attributes":')
            with self.assertRaises(ValueError):
                compare.validate_output(path, 1000)

if __name__ == '__main__':
    unittest.main()
