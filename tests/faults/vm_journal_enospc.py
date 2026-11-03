#!/usr/bin/env python3
"""Boot a child VM with a small full ext4 image and verify journal preallocation rejection."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import platform
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
    parser.add_argument("--disk-mib", type=int, default=64)
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    powerloss = load_powerloss()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    release = platform.uname().release
    config = powerloss.read_kernel_config(None, release)
    disk_interface, disk_device = powerloss.choose_disk_interface(config)
    modules = powerloss.filesystem_module_closure(release, work, config, "ext4")
    init = work / "init-journal-enospc"
    init.write_text(
        "#!/bin/busybox sh\n"
        "set -u\n"
        "export PATH=/bin\n"
        "busybox mount -t devtmpfs devtmpfs /dev\n"
        "busybox mount -t proc proc /proc\n"
        "busybox mount -t sysfs sysfs /sys\n"
        "if [ -f /etc/kron-modules ]; then\n"
        "  while read -r module; do\n"
        "    busybox insmod \"$module\" || { echo \"KRON_JOURNAL_ENOSPC_MODULE_FAILED $module\"; busybox poweroff -f; }\n"
        "  done </etc/kron-modules\n"
        "fi\n"
        "busybox mkdir -p /mnt\n"
        "busybox mount -t ext4 -o data=ordered /dev/vda /mnt || { echo KRON_JOURNAL_ENOSPC_MOUNT_FAILED; busybox poweroff -f; }\n"
        "/bin/testwriter journal-enospc --journal /mnt/kron.journal\n"
        "rc=$?\n"
        "echo KRON_JOURNAL_ENOSPC_RC=$rc\n"
        "busybox poweroff -f\n"
    )
    initramfs = powerloss.build_initramfs(work, args.busybox.resolve(), args.testwriter.resolve(), init, modules)
    disk = work / "journal-enospc.raw"
    if disk.exists():
        raise RuntimeError(f"refusing to overwrite existing evidence: {disk}")
    with disk.open("wb") as stream:
        stream.truncate(args.disk_mib * 1024 * 1024)
    subprocess.run([powerloss.require_tool("mkfs.ext4"), "-q", "-F", "-L", "KRONTEST", str(disk)], check=True)
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
        "-drive", f"file={disk},format=raw,if={disk_interface},cache=writeback",
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
        raise RuntimeError(f"journal ENOSPC VM exited with {completed.returncode}")
    for marker in ("KRON_JOURNAL_ENOSPC_FILLED", "KRON_JOURNAL_ENOSPC_REJECTED", "KRON_JOURNAL_ENOSPC_RC=0"):
        if marker not in log:
            raise RuntimeError(f"missing marker: {marker}")
    print("journal preallocation rejected on a full ext4 image")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(f"journal ENOSPC fault test failed: {error}")
        raise SystemExit(1)
