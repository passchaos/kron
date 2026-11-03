"""Independent checks for random-time process-crash evidence."""
import json
import struct
import zlib

RAW_PASSWORD = b"kron-random-crash-private-82dbdc07"
SOURCE = {"module": "random.crash.owner", "file": "runtime_crash_writer.zig",
          "function": "emitSnapshot", "line": 100, "column": 1}


def unsigned(value):
    assert ((isinstance(value, int) and not isinstance(value, bool)) or
            (isinstance(value, str) and value.isascii() and value.isdecimal())), value
    result = int(value)
    assert 0 <= result < 2**64, value
    return result


def complete_records(data):
    assert RAW_PASSWORD not in data, "raw password reached output"
    end = data.rfind(b"\n") + 1
    return [json.loads(line) for line in data[:end].splitlines()], data[end:]


def verify_event(event, ready):
    attributes = dict(event["attributes"])
    producer, identifier = unsigned(attributes["producer"]), unsigned(attributes["id"])
    assert producer < ready["producers"] and identifier < 20000
    length = 64 + (ready["seed"] % 897 + identifier * 17 + producer * 31) % 897
    payload = chr(ord("a") + (identifier + producer) % 26) * length
    for name in ("seed", "producer", "id"):
        attributes[name] = unsigned(attributes[name])
    assert attributes == {
        "seed": ready["seed"], "producer": producer, "id": identifier,
        "payload": payload, "password": "[REDACTED]",
        "nested": {"label": f"child-{ready['seed']}-{producer}-{identifier}",
                   "values": [identifier, identifier % 2 == 0,
                              "hex:" + bytes((identifier & 255, ready["seed"] & 255, producer, 255)).hex(), None],
                   "secret": "[REDACTED]"},
    }, (producer, identifier, attributes)
    assert event["message"] == f"producer {producer} event {identifier}: {payload}"
    assert event["scope"] == "crash.random" and event["severity"] == "info"
    assert event["source"] == SOURCE
    assert unsigned(event["session"]) == ready["session"]
    assert unsigned(event["timestamp_ns"]) > 0
    assert unsigned(event["route_mask"]) == unsigned(event["config_generation"]) == 1
    channel, sequence = unsigned(event["channel"]), unsigned(event["sequence"])
    assert sequence > 0
    assert channel == 0 if ready["mode"] == "shared" else 1 <= channel <= ready["producers"]
    return (producer, identifier), (ready["session"], channel, sequence)


def verify_coverage(written, recovered, acknowledgements, ready):
    by_key, by_identity = {}, {}
    channels = {}
    for origin, events in (("written", written), ("recovered", recovered)):
        local_keys = set()
        last_sequence = {}
        for event in events:
            key, identity = verify_event(event, ready)
            assert key not in local_keys, ("duplicate within", origin, key)
            local_keys.add(key)
            if key in by_key:
                assert by_key[key] == event, ("duplicate payload mismatch", key)
            if identity in by_identity:
                assert by_identity[identity] == key, ("identity collision", identity)
            by_key[key], by_identity[identity] = event, key
            producer, _ = key
            channel, sequence = identity[1:]
            if ready["mode"] == "spsc":
                assert channels.setdefault(producer, channel) == channel
            assert sequence > last_sequence.get(channel, 0), ("nonmonotonic channel", origin, identity)
            last_sequence[channel] = sequence
    if ready["mode"] == "spsc":
        assert len(set(channels.values())) == ready["producers"]
    acknowledged = set()
    for producer in range(ready["producers"]):
        ids = acknowledgements[producer]
        assert ids == list(range(len(ids))), ("ACK gap or duplicate", producer)
        assert len(ids) > ready["warm_records"], ("no post-READY progress", producer)
        acknowledged.update((producer, identifier) for identifier in ids)
    assert acknowledged <= by_key.keys(), ("lost acknowledged events", acknowledged - by_key.keys())
    extra = by_key.keys() - acknowledged
    # Each producer publishes its ACK before starting the next emit. A killed
    # call or incomplete ACK can add only the next event of that producer.
    assert extra <= {(producer, len(acknowledgements[producer])) for producer in range(ready["producers"])}, ("unexpected unacknowledged events", extra)
    warm = {(producer, identifier) for producer in range(ready["producers"]) for identifier in range(ready["warm_records"])}
    assert warm <= {(unsigned(event["attributes"]["producer"]), unsigned(event["attributes"]["id"])) for event in written}
    duplicates = len(written) + len(recovered) - len(by_key)
    return {"acknowledged": len(acknowledged), "written": len(written), "recovered": len(recovered),
            "unique": len(by_key), "overlap": duplicates, "unacknowledged_commits": len(extra)}


def committed_sequences(data, schema):
    """Check immutable headers/slot CRC with Python zlib, independently of Zig."""
    assert RAW_PASSWORD not in data, "raw password reached journal"
    def number(offset, width):
        assert 0 <= offset <= len(data) - width
        return int.from_bytes(data[offset:offset + width], "little")
    assert data[:8] == b"KRONJNL1" and number(8, 4) == (3 if schema else 1)
    assert number(12, 4) == 0x01020304 and number(56, 4) == 4096
    assert zlib.crc32(data[:60]) == number(60, 4)
    assert number(16, 8) == 16 and number(24, 8) == 4096 and number(32, 8) == 4160
    data_end = 4096 + 16 * 4160
    if schema:
        assert data[256:264] == b"KRONSCH1" and zlib.crc32(data[256:316]) == number(316, 4)
        assert number(268, 4) == 4 and number(276, 4) == 4096
        assert number(280, 8) >= data_end and number(280, 8) % 4096 == 0
        assert number(280, 8) + number(288, 8) == len(data)
    else:
        assert len(data) == data_end
    checkpoints = []
    for offset in (128, 192):
        if number(offset, 8) and zlib.crc32(data[offset:offset + 16]) == number(offset + 16, 4):
            checkpoints.append((number(offset, 8), number(offset + 8, 8)))
    assert checkpoints and max(checkpoints)[1] == 0, "workload unexpectedly reclaimed durable records"
    committed, reserved = set(), 0
    for index in range(16):
        slot = 4096 + index * 4160
        marker = number(slot, 8)
        if marker == 0:
            continue
        sequence, state = marker >> 2, marker & 3
        assert sequence > 0 and (sequence - 1) % 16 == index
        if state != 2:
            assert state in (1, 3)
            reserved += state == 1
            continue
        assert number(slot + 8, 8) == sequence
        generation = number(slot + 16, 8)
        assert generation == (sequence - 1) // 16 + 1
        length = number(slot + 24, 4)
        assert 84 <= length <= 4096
        payload = data[slot + 64:slot + 64 + length]
        assert payload[:4] == b"KRNE" and int.from_bytes(payload[4:6], "little") == (5 if schema else 4)
        checksum = struct.pack("<QQI", sequence, generation, length)
        reference = data[slot + 32:slot + 56]
        if schema:
            assert 1 <= number(slot + 32, 4) <= 4
            checksum += reference
            assert data[slot + 56:slot + 64] == bytes(8)
            checksum += bytes(8)
        else:
            assert reference == bytes(24)
        assert zlib.crc32(checksum + payload) == number(slot + 28, 4)
        assert sequence not in committed
        committed.add(sequence)
    return committed, reserved
