#!/usr/bin/env python3
"""Abrupt-QEMU power-loss gate for the kron journal/file sink.

This script never mounts the image on the host. It creates a new ext4 or xfs
raw file, boots it under QEMU TCG, waits for a durability acknowledgement from
the guest, SIGKILLs QEMU, then verifies through a temporary QEMU snapshot
overlay.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import lzma
import os
from pathlib import Path
import platform
import re
import selectors
import shutil
import signal
import subprocess
import sys
import time


ACK_RE = re.compile(rb"KRON_ACK seq=([0-9]+)")
VERIFY_RE = re.compile(rb"KRON_VERIFY_OK acked=([0-9]+)")


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise RuntimeError(f"required tool not found: {name}")
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def resolve_kernel(explicit: Path | None, work: Path) -> Path:
    if explicit is not None:
        if not os.access(explicit, os.R_OK):
            raise RuntimeError(f"kernel is not readable: {explicit}")
        return explicit

    release = platform.uname().release
    for candidate in (
        Path(f"/boot/vmlinuz-{release}"),
        Path(f"/usr/lib/modules/{release}/vmlinuz"),
        Path(f"/lib/modules/{release}/vmlinuz"),
    ):
        if candidate.is_file() and os.access(candidate, os.R_OK):
            return candidate

    # Ubuntu publishes the unsigned image in the normal signed apt repository.
    # Downloading and extracting does not install packages or require root.
    package = f"linux-image-unsigned-{release}"
    kernel_work = work / "kernel"
    kernel_work.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [require_tool("apt-get"), "download", package],
        cwd=kernel_work,
        check=True,
    )
    debs = sorted(kernel_work.glob(f"{package}_*.deb"))
    if not debs:
        raise RuntimeError(f"apt downloaded no .deb for {package}")
    extracted = kernel_work / "extracted"
    extracted.mkdir(exist_ok=True)
    subprocess.run(
        [require_tool("dpkg-deb"), "-x", str(debs[-1]), str(extracted)],
        check=True,
    )
    kernels = sorted((extracted / "boot").glob(f"vmlinuz-{release}"))
    if not kernels:
        raise RuntimeError(f"downloaded package did not contain vmlinuz-{release}")
    return kernels[0]


def resolve_busybox(explicit: Path, work: Path) -> Path:
    if explicit.is_file():
        description = subprocess.run(
            [require_tool("file"), "-b", str(explicit)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout
        if "statically linked" in description:
            return explicit

    package_work = work / "busybox"
    package_work.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [require_tool("apt-get"), "download", "busybox-static"],
        cwd=package_work,
        check=True,
    )
    debs = sorted(package_work.glob("busybox-static_*.deb"))
    if not debs:
        raise RuntimeError("apt downloaded no busybox-static .deb")
    extracted = package_work / "extracted"
    extracted.mkdir(exist_ok=True)
    subprocess.run(
        [require_tool("dpkg-deb"), "-x", str(debs[-1]), str(extracted)],
        check=True,
    )
    candidates = list(extracted.glob("**/busybox"))
    if not candidates:
        raise RuntimeError("busybox-static package contained no busybox executable")
    return candidates[0]


def read_kernel_config(explicit: Path | None, release: str) -> dict[str, str]:
    config = explicit or Path(f"/boot/config-{release}")
    if not config.is_file() or not os.access(config, os.R_OK):
        raise RuntimeError(
            f"matching readable kernel config unavailable for {release}; use --kernel-config"
        )
    values: dict[str, str] = {}
    for line in config.read_text().splitlines():
        if line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def choose_disk_interface(config: dict[str, str]) -> tuple[str, str]:
    if all(config.get(key) == "y" for key in (
        "CONFIG_VIRTIO", "CONFIG_VIRTIO_PCI", "CONFIG_VIRTIO_BLK"
    )):
        return "virtio", "/dev/vda"
    if all(config.get(key) == "y" for key in (
        "CONFIG_SCSI", "CONFIG_BLK_DEV_SD", "CONFIG_ATA", "CONFIG_ATA_PIIX"
    )):
        return "ide", "/dev/sda"
    raise RuntimeError(
        "neither virtio-blk nor QEMU IDE/SCSI path is built into the kernel; "
        "supply a kernel with one built in or extend the module manifest"
    )


def module_name(path: str) -> str:
    return re.sub(r"\.ko(?:\..*)?$", "", Path(path).name).replace("-", "_")


def filesystem_module_closure(release: str, work: Path, config: dict[str, str], filesystem: str) -> list[Path]:
    config_key, root_name = {
        "ext4": ("CONFIG_EXT4_FS", "ext4"),
        "xfs": ("CONFIG_XFS_FS", "xfs"),
        "btrfs": ("CONFIG_BTRFS_FS", "btrfs"),
        "f2fs": ("CONFIG_F2FS_FS", "f2fs"),
    }[filesystem]
    if config.get(config_key) == "y":
        return []
    if config.get(config_key) != "m":
        raise RuntimeError(f"kernel has no {filesystem} support")

    module_root = Path(f"/lib/modules/{release}")
    if not (module_root / "modules.dep").is_file():
        package = f"linux-modules-{release}"
        module_work = work / "modules"
        module_work.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [require_tool("apt-get"), "download", package],
            cwd=module_work,
            check=True,
        )
        debs = sorted(module_work.glob(f"{package}_*.deb"))
        if not debs:
            raise RuntimeError(f"apt downloaded no .deb for {package}")
        extracted = module_work / "extracted"
        extracted.mkdir(exist_ok=True)
        subprocess.run(
            [require_tool("dpkg-deb"), "-x", str(debs[-1]), str(extracted)],
            check=True,
        )
        module_root = extracted / "lib" / "modules" / release

    dependencies: dict[str, list[str]] = {}
    by_name: dict[str, str] = {}
    for line in (module_root / "modules.dep").read_text().splitlines():
        owner, raw_dependencies = line.split(":", 1)
        dependencies[owner] = raw_dependencies.split()
        by_name[module_name(owner)] = owner
    root_module = by_name.get(root_name)
    if root_module is None:
        raise RuntimeError(f"{config_key}=m but {root_name} module is absent")

    ordered: list[str] = []
    visited: set[str] = set()

    def add(path: str) -> None:
        if path in visited:
            return
        visited.add(path)
        for dependency in dependencies.get(path, []):
            add(dependency)
        ordered.append(path)

    # F2FS resolves its CRC through the crypto API at mount time; the crypto
    # provider is not a modules.dep dependency of f2fs.ko.
    extras = {"f2fs": ("crc32_generic",)}.get(filesystem, ())
    for extra in extras:
        path = by_name.get(extra)
        if path is None:
            raise RuntimeError(f"{filesystem} requires missing module {extra}")
        add(path)
    add(root_module)
    return [module_root / path for path in ordered]


def copy_module_uncompressed(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.suffix == ".zst":
        with destination.open("wb") as output:
            subprocess.run([require_tool("zstd"), "-q", "-d", "-c", str(source)], stdout=output, check=True)
    elif source.suffix == ".xz":
        destination.write_bytes(lzma.decompress(source.read_bytes()))
    elif source.suffix == ".gz":
        destination.write_bytes(gzip.decompress(source.read_bytes()))
    else:
        shutil.copy2(source, destination)


def build_initramfs(
    root: Path,
    busybox: Path,
    testwriter: Path,
    init: Path,
    modules: list[Path],
) -> Path:
    tree = root / "initramfs"
    for directory in ("bin", "dev", "proc", "sys", "mnt"):
        (tree / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(busybox, tree / "bin" / "busybox")
    shutil.copy2(testwriter, tree / "bin" / "testwriter")
    shutil.copy2(init, tree / "init")
    os.chmod(tree / "init", 0o755)
    os.chmod(tree / "bin" / "testwriter", 0o755)
    sh_link = tree / "bin" / "sh"
    if not sh_link.exists():
        sh_link.symlink_to("busybox")

    if modules:
        manifest: list[str] = []
        for index, source in enumerate(modules):
            destination = tree / "lib" / "kron-modules" / f"{index:03d}-{module_name(source.name)}.ko"
            copy_module_uncompressed(source, destination)
            manifest.append("/" + str(destination.relative_to(tree)))
        etc = tree / "etc"
        etc.mkdir(exist_ok=True)
        (etc / "kron-modules").write_text("\n".join(manifest) + "\n")

    entries = ["."] + sorted(
        str(path.relative_to(tree)) for path in tree.rglob("*")
    )
    listing = ("\0".join(entries) + "\0").encode()
    archive = subprocess.run(
        [require_tool("cpio"), "--null", "--create", "--format=newc", "--quiet"],
        cwd=tree,
        input=listing,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    output = root / "initramfs.cpio.gz"
    output.write_bytes(gzip.compress(archive, compresslevel=1, mtime=0))
    return output


def qemu_command(
    kernel: Path,
    initramfs: Path,
    disk: Path,
    mode: str,
    acked: int = 0,
    snapshot: bool = False,
    disk_interface: str = "virtio",
    disk_device: str = "/dev/vda",
    schema: bool = False,
    filesystem: str = "ext4",
) -> list[str]:
    command = [
        require_tool("qemu-system-x86_64"),
        "-accel", "tcg,thread=multi",
        "-machine", "pc",
        "-cpu", "max",
        "-m", "256M",
        "-smp", "1",
        "-kernel", str(kernel),
        "-initrd", str(initramfs),
        "-append", (
            f"console=ttyS0 panic=-1 loglevel=3 kron.mode={mode} "
            f"kron.acked={acked} kron.device={disk_device} kron.schema={int(schema)} "
            f"kron.fs={filesystem}"
        ),
        "-drive", f"file={disk},format=raw,if={disk_interface},cache=writeback",
        "-display", "none",
        "-serial", "stdio",
        "-monitor", "none",
        "-no-reboot",
    ]
    if snapshot:
        command.append("-snapshot")
    return command


def run_until_ack(command: list[str], log: Path, timeout: float, ack_count: int) -> tuple[subprocess.Popen[bytes], int]:
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    seen = 0
    latest = -1
    pending = b""
    try:
        with log.open("wb") as transcript:
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"writer VM exited before acknowledgement: {process.returncode}")
                for key, _ in selector.select(timeout=0.25):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        continue
                    transcript.write(chunk)
                    transcript.flush()
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                    pending = (pending + chunk)[-131072:]
                    matches = list(ACK_RE.finditer(pending))
                    if len(matches) > seen:
                        seen = len(matches)
                        latest = int(matches[-1].group(1))
                        if seen >= ack_count:
                            return process, latest
            raise TimeoutError("timed out waiting for KRON_ACK")
    except BaseException:
        if process.poll() is None:
            kill_vm(process)
        raise


def kill_vm(process: subprocess.Popen[bytes]) -> None:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=10)


def run_verify(command: list[str], log: Path, timeout: float, acked: int) -> None:
    result = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    log.write_bytes(result.stdout)
    sys.stdout.buffer.write(result.stdout)
    match = VERIFY_RE.search(result.stdout)
    if result.returncode != 0 or match is None or int(match.group(1)) != acked:
        raise RuntimeError("verification VM did not confirm the acknowledged sequence")


def resolve_mkfs(filesystem: str, work: Path) -> list[str]:
    if filesystem == "ext4":
        return [require_tool("mkfs.ext4"), "-q", "-F", "-L", "KRONTEST"]
    tools = {
        "xfs": ("mkfs.xfs", "xfsprogs"),
        "btrfs": ("mkfs.btrfs", "btrfs-progs"),
        "f2fs": ("mkfs.f2fs", "f2fs-tools"),
    }
    if filesystem not in tools:
        raise RuntimeError(f"unsupported filesystem: {filesystem}")
    tool_name, package = tools[filesystem]
    tool = shutil.which(tool_name)
    if tool is None:
        tool_work = work / package
        tool_work.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [require_tool("apt-get"), "download", package],
            cwd=tool_work,
            check=True,
        )
        debs = sorted(tool_work.glob(f"{package}_*.deb"))
        if not debs:
            raise RuntimeError(f"apt downloaded no .deb for {package}")
        extracted = tool_work / "extracted"
        extracted.mkdir(exist_ok=True)
        subprocess.run(
            [require_tool("dpkg-deb"), "-x", str(debs[-1]), str(extracted)],
            check=True,
        )
        tool = str(extracted / "sbin" / tool_name)
        if not Path(tool).is_file():
            raise RuntimeError(f"{package} package has no sbin/{tool_name}")
    label_option = "-l" if filesystem == "f2fs" else "-L"
    return [tool, "-q", "-f", label_option, "KRONTEST"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--testwriter", required=True, type=Path)
    parser.add_argument("--kernel", type=Path)
    parser.add_argument("--kernel-config", type=Path)
    parser.add_argument("--busybox", type=Path, default=Path("/usr/bin/busybox"))
    parser.add_argument("--work-dir", type=Path, default=Path(f"/tmp/kron-power-loss-{os.getpid()}"))
    parser.add_argument("--disk-mib", type=int, default=256)
    parser.add_argument("--filesystem", choices=("ext4", "xfs", "btrfs", "f2fs"), default="ext4")
    parser.add_argument("--kill-after-acks", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--schema", action="store_true", help="Exercise the v2 persistent schema-reference path")
    args = parser.parse_args()

    if not args.testwriter.is_file():
        raise RuntimeError(f"testwriter not found: {args.testwriter}")
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    release = platform.uname().release
    kernel = resolve_kernel(args.kernel, work)
    config = read_kernel_config(args.kernel_config, release)
    disk_interface, disk_device = choose_disk_interface(config)
    modules = filesystem_module_closure(release, work, config, args.filesystem)
    busybox = resolve_busybox(args.busybox, work)
    initramfs = build_initramfs(
        work,
        busybox.resolve(),
        args.testwriter.resolve(),
        Path(__file__).with_name("guest_init"),
        modules,
    )
    disk = work / "scratch.raw"
    if disk.exists():
        raise RuntimeError(f"refusing to overwrite existing crash evidence: {disk}")
    disk_mib = args.disk_mib
    if args.filesystem in ("xfs", "btrfs") and disk_mib < 512:
        # mkfs.xfs rejects images at or below 300 MiB; keep the gate usable
        # with its smaller default while recording the actual image size.
        disk_mib = 512
    with disk.open("wb") as stream:
        stream.truncate(disk_mib * 1024 * 1024)
    subprocess.run(resolve_mkfs(args.filesystem, work) + [str(disk)], check=True)

    writer, acked = run_until_ack(
        qemu_command(
            kernel, initramfs, disk, "write",
            disk_interface=disk_interface,
            disk_device=disk_device,
            schema=args.schema,
            filesystem=args.filesystem,
        ),
        work / "writer-serial.log",
        args.timeout,
        args.kill_after_acks,
    )
    kill_vm(writer)
    crash_hash = sha256(disk)

    if args.filesystem == "ext4":
        # Read-only diagnostic: -n never repairs or modifies the image.
        check = subprocess.run(
            [require_tool("e2fsck"), "-f", "-n", str(disk)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        (work / "e2fsck-readonly.log").write_bytes(check.stdout)

    run_verify(
        qemu_command(
            kernel, initramfs, disk, "verify", acked=acked, snapshot=True,
            disk_interface=disk_interface,
            disk_device=disk_device,
            schema=args.schema,
            filesystem=args.filesystem,
        ),
        work / "verify-serial.log",
        args.timeout,
        acked,
    )
    if sha256(disk) != crash_hash:
        raise RuntimeError("verification changed the crash-evidence base image")

    print(f"PASS: acknowledged seq {acked} survived abrupt QEMU death")
    print(f"evidence: {work}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, TimeoutError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
