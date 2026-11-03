#!/usr/bin/env python3
"""Boot a child VM with a small tmpfs and exercise a real ENOSPC FileSink path."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import subprocess


def load_powerloss():
    path = Path(__file__).resolve().parents[1] / "power_loss" / "vm_powerloss.py"
    spec = importlib.util.spec_from_file_location("kron_vm_powerloss", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--testwriter", required=True, type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--busybox", required=True, type=Path)
    parser.add_argument("--work-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    powerloss = load_powerloss()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    init = work / "init-enospc"
    init.write_text(
        "#!/bin/busybox sh\n"
        "set -u\n"
        "export PATH=/bin\n"
        "busybox mount -t devtmpfs devtmpfs /dev\n"
        "busybox mount -t proc proc /proc\n"
        "busybox mount -t sysfs sysfs /sys\n"
        "busybox mkdir -p /mnt\n"
        "busybox mount -t tmpfs -o size=1M tmpfs /mnt || { echo KRON_ENOSPC_MOUNT_FAILED; busybox poweroff -f; }\n"
        "/bin/testwriter enospc --journal /mnt/kron.journal --output /mnt/kron.log\n"
        "rc=$?\n"
        "echo KRON_ENOSPC_RC=$rc\n"
        "busybox poweroff -f\n"
    )
    initramfs = powerloss.build_initramfs(work, args.busybox.resolve(), args.testwriter.resolve(), init, [])
    command = [
        "qemu-system-x86_64",
        "-accel", "tcg,thread=multi",
        "-machine", "pc",
        "-cpu", "max",
        "-m", "256M",
        "-smp", "1",
        "-kernel", str(args.kernel),
        "-initrd", str(initramfs),
        "-append", "console=ttyS0 panic=-1 loglevel=3",
        "-display", "none",
        "-serial", "stdio",
        "-monitor", "none",
        "-no-reboot",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout)
    log = completed.stdout + completed.stderr
    (work / "serial.log").write_text(log)
    print(log, end="")
    if completed.returncode != 0:
        raise RuntimeError(f"ENOSPC VM exited with {completed.returncode}")
    for marker in ("KRON_ENOSPC_FILLED", "KRON_ENOSPC_LATCHED", "KRON_ENOSPC_RC=0"):
        if marker not in log:
            raise RuntimeError(f"missing marker: {marker}")
    print("ENOSPC FileSink path latched without a successful flush")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(f"ENOSPC fault test failed: {error}")
        raise SystemExit(1)
