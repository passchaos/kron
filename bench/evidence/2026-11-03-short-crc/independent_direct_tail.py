#!/usr/bin/env python3
"""Independent full-seed IEEE oracle for the proposed 20/24-byte embeddings."""
import random

MASK64 = (1 << 64) - 1
LANE_MASK = 0xFFFFFFFF | (0xFFFFFFFF << 64)
C96 = 0x00CCAA009E
C64 = 0x0163CD6124
POLY_REVERSED = 0x01DB710641
BARRETT = 0x01F7011641


def clmul(a, b):
    value = 0
    while b:
        if b & 1:
            value ^= a
        b >>= 1
        a <<= 1
    return value


def reduce128(value):
    value = (value >> 64) ^ clmul(value & MASK64, C96)
    low = value >> 32
    value &= LANE_MASK
    value = clmul(value & MASK64, C64) ^ low
    first = clmul((value & LANE_MASK) & MASK64, BARRETT)
    second = clmul((first & LANE_MASK) & MASK64, POLY_REVERSED)
    value ^= second
    return (value >> 32) & 0xFFFFFFFF


def coefficient(exponent):
    value = 1
    for _ in range(exponent):
        value <<= 1
        if value & (1 << 32):
            value ^= 0x104C11DB7
    return int(f"{value:032b}"[::-1], 2) << 1


def bitwise_oracle(state, data):
    for byte in data:
        state ^= byte
        for _ in range(8):
            state = (state >> 1) ^ (0xEDB88320 if state & 1 else 0)
    return state


def main():
    assert coefficient(64) == C64
    assert coefficient(96) == C96
    assert coefficient(32) == 0x1DB710640
    rng = random.Random(0x6372637461696C)
    checks = 0
    for length in (20, 24):
        inputs = [(0, (1 << bit).to_bytes(length, "little")) for bit in range(length * 8)]
        inputs += [(1 << bit, bytes(length)) for bit in range(32)]
        inputs += [(rng.randrange(1 << 32), rng.randbytes(length)) for _ in range(10000)]
        for state, data in inputs:
            vector = int.from_bytes(data[:16], "little") ^ state
            lo, hi = vector & MASK64, vector >> 64
            tail = int.from_bytes(data[16:], "little")
            combined = (
                clmul(lo, C64) ^ (hi << 32) ^ (tail << 96)
                if length == 20
                else clmul(lo, C96) ^ clmul(hi, coefficient(32)) ^ (tail << 64)
            )
            assert reduce128(combined) == bitwise_oracle(state, data)
            checks += 1
    print(f"{checks} independent raw IEEE cases passed; no Zig or speed qualification")


if __name__ == "__main__":
    main()
