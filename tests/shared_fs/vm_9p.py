#!/usr/bin/env python3
"""Boot a child VM with a 9p host share and run the public package consumer.

This is a filesystem-behavior qualification, not a crash or power-loss test.
The host share is never mounted on the host; QEMU serves it over virtio-9p.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import platform
import subprocess
import sys


def load_powerloss():
    path = Path(__file__).resolve().parents[1] / "power_loss" / "vm_powerloss.py"
    spec = importlib.util.spec_from_file_location("kron_vm_powerloss", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def module_closure(release: str, work: Path, roots: tuple[str, ...]) -> list[Path]:
    module_root = Path(f"/lib/modules/{release}")
    if not (module_root / "modules.dep").is_file():
        package = f"linux-modules-{release}"
        module_work = work / "modules"
        module_work.mkdir(parents=True, exist_ok=True)
        subprocess.run(["apt-get", "download", package], cwd=module_work, check=True)
        debs = sorted(module_work.glob(f"{package}_*.deb"))
        if not debs:
            raise RuntimeError(f"apt downloaded no .deb for {package}")
        extracted = module_work / "extracted"
        extracted.mkdir(exist_ok=True)
        subprocess.run(["dpkg-deb", "-x", str(debs[-1]), str(extracted)], check=True)
        module_root = extracted / "lib" / "modules" / release

    dependencies: dict[str, list[str]] = {}
    by_name: dict[str, str] = {}
    for line in (module_root / "modules.dep").read_text().splitlines():
        owner, raw_dependencies = line.split(":", 1)
        dependencies[owner] = raw_dependencies.split()
        by_name[owner.rsplit("/", 1)[-1].split(".")[0].replace("-", "_")] = owner

    ordered: list[str] = []
    visited: set[str] = set()

    def add(path: str) -> None:
        if path in visited:
            return
        visited.add(path)
        for dependency in dependencies.get(path, []):
            add(dependency)
        ordered.append(path)

    for root in roots:
        path = by_name.get(root)
        if path is None:
            raise RuntimeError(f"kernel module {root} is absent")
        add(path)
    return [module_root / path for path in ordered]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", required=True, type=Path)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--busybox", required=True, type=Path)
    parser.add_argument("--share", required=True, type=Path)
    parser.add_argument("--work-dir", required=True, type=Path)
    parser.add_argument("--mode", default="all", choices=("all", "qualify", "sync", "memory", "mmap", "spsc_memory", "spsc_mmap"))
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    powerloss = load_powerloss()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    share = args.share.resolve()
    share.mkdir(parents=True, exist_ok=True)
    release = platform.uname().release
    modules = module_closure(release, work, ("9p", "9pnet", "9pnet_virtio", "netfs"))
    init = work / "init-9p"
    init.write_text(
        "#!/bin/busybox sh\n"
        "set -u\n"
        "export PATH=/bin\n"
        "busybox mount -t devtmpfs devtmpfs /dev\n"
        "busybox mount -t proc proc /proc\n"
        "busybox mount -t sysfs sysfs /sys\n"
        "mode=qualify\n"
        "for arg in $(busybox cat /proc/cmdline); do\n"
        "  case \"$arg\" in kron.mode=*) mode=\"${arg#kron.mode=}\" ;; esac\n"
        "done\n"
        "if [ -f /etc/kron-modules ]; then\n"
        "  while read -r module; do\n"
        "    busybox insmod \"$module\" || { echo \"KRON_9P_MODULE_FAILED $module\"; busybox poweroff -f; }\n"
        "  done </etc/kron-modules\n"
        "fi\n"
        "busybox mkdir -p /mnt\n"
        "busybox mount -t 9p -o trans=virtio,version=9p2000.L,msize=131072 hostshare /mnt || { echo KRON_9P_MOUNT_FAILED; busybox poweroff -f; }\n"
        "if [ \"$mode\" = qualify ]; then\n"
        "  /bin/testwriter qualify /mnt/qualify\n"
        "else\n"
        "  /bin/testwriter \"$mode\" /mnt/\"$mode\"\n"
        "fi\n"
        "rc=$?\n"
        "echo KRON_9P_MODE=$mode\n"
        "echo KRON_9P_RC=$rc\n"
        "busybox poweroff -f\n"
    )
    initramfs = powerloss.build_initramfs(work, args.busybox.resolve(), args.consumer.resolve(), init, modules)
    modes = ("qualify", "sync", "memory", "mmap", "spsc_memory", "spsc_mmap") if args.mode == "all" else (args.mode,)
    results = []
    for mode in modes:
        command = [
            "qemu-system-x86_64",
            "-accel", "tcg,thread=multi",
            "-machine", "pc",
            "-cpu", "max",
            "-m", "256M",
            "-smp", "1",
            "-kernel", str(args.kernel),
            "-initrd", str(initramfs),
            "-append", f"console=ttyS0 panic=-1 loglevel=3 kron.mode={mode}",
            "-virtfs", f"local,path={share},mount_tag=hostshare,security_model=none",
            "-display", "none",
            "-serial", "stdio",
            "-monitor", "none",
            "-no-reboot",
        ]
        completed = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout)
        log = completed.stdout + completed.stderr
        (work / f"{mode}-serial.log").write_text(log)
        rc_match = [line for line in log.splitlines() if line.startswith("KRON_9P_RC=")]
        rc = int(rc_match[-1].split("=", 1)[1]) if rc_match else None
        json_lines = [line for line in log.splitlines() if line.startswith("{")]
        report = json.loads(json_lines[-1]) if json_lines else None
        expected_ok = mode in ("sync", "memory", "spsc_memory")
        if expected_ok:
            if rc != 0 or report is None:
                raise RuntimeError(f"9p {mode} did not complete: rc={rc} log={log}")
            if report["accepted"] != report["written"] or report["pending"] != 0:
                raise RuntimeError(f"9p {mode} health mismatch: {report}")
            print(f"9p {mode}: accepted=written={report['accepted']} pending=0")
        else:
            if mode == "qualify":
                if rc != 0 and "PreallocationUnsupported" in log:
                    print(f"9p qualify: rejected PreallocationUnsupported (rc={rc})")
                else:
                    raise RuntimeError(f"9p qualify did not reject preallocation: rc={rc} log={log}")
            elif "PreallocationUnsupported" not in log:
                raise RuntimeError(f"9p {mode} did not reject preallocation: rc={rc} log={log}")
            else:
                print(f"9p {mode}: rejected PreallocationUnsupported before success")
        results.append({"mode": mode, "rc": rc, "report": report})
    print(f"9p modes complete: {len(results)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"9p qualification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
