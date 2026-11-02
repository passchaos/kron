#!/usr/bin/env python3
"""CRC-32/ISO-HDLC polynomial proof and independent byte-oracle checks."""
import json
import random
import zlib
from pathlib import Path

P = 0x104C11DB7
MASK = 0xFFFFFFFF


def rem(v):
    while v.bit_length() > 32:
        v ^= P << (v.bit_length() - 33)
    return v


def reverse(v, width):
    return int(f"{v:0{width}b}"[::-1], 2)


def constants(distance):
    return (reverse(rem(1 << (distance + 32)), 32) << 1,
            reverse(rem(1 << (distance - 32)), 32) << 1)


def clmul(a, b):
    result = 0
    while a:
        bit = a & -a
        result ^= b << (bit.bit_length() - 1)
        a ^= bit
    return result


def fold(v, distance):
    lo, hi = constants(distance)
    return clmul(v & ((1 << 64) - 1), lo) ^ clmul(v >> 64, hi)


def raw_register(v):
    # Definition directly from the normal IEEE generator polynomial, without
    # using production Barrett-reduction constants or any CRC slicing table.
    return reverse(rem(reverse(v, 128) << 32), 32)


def bit_oracle(state, data):
    for byte in data:
        state ^= byte
        for _ in range(8):
            state = (state >> 1) ^ (0xEDB88320 if state & 1 else 0)
    return state


def collapse(xs, mode):
    a, b, c, d = xs
    if mode == "serial":
        return fold(fold(fold(a, 128) ^ b, 128) ^ c, 128) ^ d
    if mode == "parallel":
        return fold(a, 384) ^ fold(b, 256) ^ fold(c, 128) ^ d
    if mode == "tree":
        return fold(fold(a, 128) ^ b, 256) ^ fold(c, 128) ^ d
    raise ValueError(mode)


def update(state, data, mode):
    assert len(data) >= 64 and len(data) % 16 == 0
    xs = [int.from_bytes(data[i:i + 16], "little") for i in (0, 16, 32, 48)]
    xs[0] ^= state
    offset = 64
    while len(data) - offset >= 64:
        xs = [fold(x, 512) ^ int.from_bytes(data[offset + i:offset + i + 16], "little")
              for x, i in zip(xs, (0, 16, 32, 48))]
        offset += 64
    value = collapse(xs, mode)
    while offset < len(data):
        value = fold(value, 128) ^ int.from_bytes(data[offset:offset + 16], "little")
        offset += 16
    return raw_register(value)


def main():
    assert constants(128) == (0x1751997D0, 0x0CCAA009E)
    assert constants(512) == (0x154442BD4, 0x1C6E41596)
    basis_checks = 0
    for distance in (128, 256, 384, 512):
        for bit in range(128):
            word = 1 << bit
            expected = reverse(rem(reverse(word, 128) << (distance + 32)), 32)
            assert raw_register(fold(word, distance)) == expected, (distance, bit)
            basis_checks += 1
    # All maps are GF(2)-linear. Exhausting these 512 independent input basis
    # vectors proves the collapse identity for every possible four-lane value.
    unequal_representatives = 0
    collapse_checks = 0
    for bit in range(512):
        xs = [0] * 4
        xs[bit // 128] = 1 << (bit % 128)
        serial = collapse(xs, "serial")
        data = (1 << bit).to_bytes(64, "little")
        expected = bit_oracle(0, data)
        for mode in ("serial", "parallel", "tree"):
            value = collapse(xs, mode)
            assert raw_register(value) == expected, (bit, mode)
            unequal_representatives += value != serial
            collapse_checks += 1
    rng = random.Random(0x4352435F4D415448)
    oracle_cases = 0
    for length in (64, 80, 96, 112, 128, 144, 192, 256, 512, 1024, 4096):
        for _ in range(12):
            data = rng.randbytes(length)
            state = rng.getrandbits(32)
            expected = bit_oracle(state, data)
            assert expected == (zlib.crc32(data, state ^ MASK) ^ MASK)
            for mode in ("serial", "parallel", "tree"):
                assert update(state, data, mode) == expected, (length, state, mode)
                oracle_cases += 1
    report = {
        "normal_polynomial": hex(P),
        "constant_formula": "(reverse32(x^(d+32) mod P)<<1, reverse32(x^(d-32) mod P)<<1)",
        "constants": {str(d): [hex(x) for x in constants(d)] for d in (128, 256, 384, 512)},
        "fold_basis_checks": basis_checks,
        "collapse_basis_checks": collapse_checks,
        "unequal_128bit_representatives": unequal_representatives,
        "random_arbitrary_seed_oracle_cases": oracle_cases,
        "result": "all passed",
    }
    print(json.dumps(report, indent=2))
    Path(__file__).with_name("math-result.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
