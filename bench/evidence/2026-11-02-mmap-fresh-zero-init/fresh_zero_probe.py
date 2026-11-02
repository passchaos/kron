#!/usr/bin/env python3
"""Check the Linux ext4 fresh-file zero contract used by header-only mmap init."""
import hashlib
import json
import os
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SIZE = 16 * 1024 * 1024


def probe(label):
    fd, path = tempfile.mkstemp(prefix=f"kron-fresh-zero-{label}-", dir=ROOT)
    try:
        if label == "truncated":
            os.write(fd, b"X" * 4096)
            os.ftruncate(fd, 0)
        os.ftruncate(fd, SIZE)
        os.posix_fallocate(fd, 0, SIZE)
        os.lseek(fd, 0, os.SEEK_SET)
        data = os.read(fd, SIZE)
        return {"label": label, "size": len(data), "nonzero_bytes": sum(byte != 0 for byte in data),
                "sha256": hashlib.sha256(data).hexdigest()}
    finally:
        os.close(fd)
        os.unlink(path)


def main():
    results = [probe("new"), probe("truncated")]
    destination = Path(__file__).resolve().parent / "fresh-zero-results.json"
    assert not destination.exists(), "Preserve prior capture"
    destination.write_text(json.dumps(results, indent=2) + "\n")
    for row in results:
        print(row["label"], row["size"], row["nonzero_bytes"], row["sha256"])


if __name__ == "__main__":
    main()
