#!/usr/bin/env python3
"""Negative evidence checks: a broken recovery must not pass the campaign."""
import copy
import struct
import unittest
import zlib

from runtime_crash_oracle import SOURCE, committed_sequences, complete_records, unsigned, verify_coverage


def event(producer, identifier):
    seed = 20261031
    length = 64 + (seed % 897 + identifier * 17 + producer * 31) % 897
    payload = chr(ord("a") + (identifier + producer) % 26) * length
    return {"attributes": {"seed": seed, "producer": producer, "id": identifier, "payload": payload,
                           "password": "[REDACTED]", "nested": {"label": f"child-{seed}-{producer}-{identifier}",
                           "values": [identifier, identifier % 2 == 0, "hex:" + bytes((identifier & 255, seed & 255, producer, 255)).hex(), None], "secret": "[REDACTED]"}},
            "message": f"producer {producer} event {identifier}: {payload}", "scope": "crash.random", "severity": "info",
            "source": SOURCE, "session": 17, "timestamp_ns": 123, "route_mask": 1, "config_generation": 1,
            "channel": 0, "sequence": identifier * 2 + producer + 1}


class OracleTests(unittest.TestCase):
    def setUp(self):
        self.ready = {"seed": 20261031, "session": 17, "mode": "shared", "schema": False, "producers": 2, "warm_records": 64}
        self.acks = [list(range(65)), list(range(65))]
        self.written = [event(producer, identifier) for identifier in range(64) for producer in range(2)]
        self.recovered = [event(0, 64), event(1, 64)]

    def verify(self, written=None, recovered=None):
        return verify_coverage(self.written if written is None else written,
                               self.recovered if recovered is None else recovered, self.acks, self.ready)

    def test_complete_prefix_recovery_overlap_and_one_inflight_are_valid(self):
        self.assertEqual(self.verify()["acknowledged"], 130)
        written = self.written + [self.recovered[0]]
        recovered = self.recovered + [event(0, 65)]
        counts = self.verify(written, recovered)
        self.assertEqual((counts["overlap"], counts["unacknowledged_commits"]), (1, 1))

    def test_missing_ack_duplicate_corrupt_snapshot_and_identity_collision_fail(self):
        mutations = [self.recovered[1:], self.recovered + [self.recovered[0]], copy.deepcopy(self.recovered), copy.deepcopy(self.recovered)]
        mutations[2][0]["attributes"]["nested"]["label"] = "reused storage"
        mutations[3][1]["sequence"] = mutations[3][0]["sequence"]
        for recovered in mutations:
            with self.subTest(recovered=recovered), self.assertRaises(AssertionError):
                self.verify(recovered=recovered)

    def test_unconfirmed_gap_and_unwritten_warm_prefix_fail(self):
        with self.assertRaises(AssertionError):
            self.verify(recovered=self.recovered + [event(0, 66)])
        with self.assertRaises(AssertionError):
            self.verify(written=self.written[1:], recovered=[self.written[0]] + self.recovered)

    def test_ack_gaps_and_cross_channel_spsc_alias_fail(self):
        self.acks[0][3] = 4
        with self.assertRaises(AssertionError):
            self.verify()
        self.acks[0] = list(range(65))
        self.ready["mode"] = "spsc"
        for current in self.written + self.recovered:
            current["channel"] = 1
        with self.assertRaises(AssertionError):
            self.verify()

    def test_full_width_integer_and_partial_json_boundaries(self):
        self.assertEqual(unsigned(str(2**64 - 1)), 2**64 - 1)
        for value in (True, 1.0, "-1", " 1", "+1", "١", str(2**64)):
            with self.subTest(value=value), self.assertRaises(AssertionError):
                unsigned(value)
        records, tail = complete_records(b'{"complete":true}\n{"partial":')
        self.assertEqual(records, [{"complete": True}])
        self.assertEqual(tail, b'{"partial":')
        with self.assertRaises(AssertionError):
            complete_records(b'kron-random-crash-private-82dbdc07')

    def test_independent_crc_rejects_committed_corruption_and_ignores_reservations(self):
        image = bytearray(4096 + 16 * 4160)
        image[:8] = b"KRONJNL1"
        struct.pack_into("<IIQQQ", image, 8, 1, 0x01020304, 16, 4096, 4160)
        struct.pack_into("<I", image, 56, 4096)
        struct.pack_into("<I", image, 60, zlib.crc32(image[:60]))
        struct.pack_into("<QQI", image, 128, 1, 0, zlib.crc32(struct.pack("<QQ", 1, 0)))
        slot = 4096
        payload = bytearray(84)
        payload[:4] = b"KRNE"
        struct.pack_into("<H", payload, 4, 4)
        struct.pack_into("<QQQII", image, slot, 6, 1, 1, 84, zlib.crc32(struct.pack("<QQI", 1, 1, 84) + payload))
        image[slot + 64:slot + 148] = payload
        struct.pack_into("<Q", image, slot + 4160, 9)  # sequence 2 reserved
        self.assertEqual(committed_sequences(image, False), ({1}, 1))
        image[slot + 80] ^= 1
        with self.assertRaises(AssertionError):
            committed_sequences(image, False)


if __name__ == "__main__":
    unittest.main()
