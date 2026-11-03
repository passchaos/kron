# QEMU power-loss gate

This gate boots the real test writer in a child Linux VM, waits until the
writer reports a durability acknowledgement, and sends `SIGKILL` to the QEMU
process. It does **not** send a signal to the application and never mounts the
test filesystem on the host.

The second boot uses QEMU `-snapshot`. Ext4 or XFS can replay its journal into
the temporary overlay, while the original raw crash image remains byte-for-byte
unchanged.

## Test writer contract

The harness embeds a statically linked executable as `/bin/testwriter` and
calls it as follows:

```text
testwriter write --journal /mnt/kron.journal --output /mnt/kron.log
testwriter verify --journal /mnt/kron.journal --output /mnt/kron.log --acked N
```

Writer mode must print this marker only after sequence `N` has met the public
durability contract (a trailing newline is accepted but not required):

```text
KRON_ACK seq=N
```

It should continue submitting records so the host can kill QEMU at arbitrary
acknowledgement boundaries. Verify mode must return success only when:

- journal recovery accepts one valid highest-generation checkpoint;
- recovered/output high-water marks are at least `N`;
- every acknowledged record through `N` is present and valid in the promised
  sink output;
- malformed tails, duplicate sequence numbers, or gaps through `N` fail.

The guest init prints `KRON_VERIFY_OK acked=N` only after verifier exit status
zero.

## Run

```sh
python3 tests/power_loss/vm_powerloss.py \
  --testwriter zig-out/bin/kron-powerloss-writer \
  --work-dir /tmp/kron-power-loss-run
```

Pass `--filesystem xfs`, `--filesystem btrfs`, or `--filesystem f2fs` to run
the same gate on those filesystems; the harness then uses a 512 MiB image for
XFS/Btrfs (mkfs.xfs rejects images at or below 300 MiB) and downloads the
matching tools package with `apt-get download` if the `mkfs` tool is not on the
host. F2FS additionally loads `crc32_generic`, which is not a `modules.dep`
dependency of `f2fs.ko`. The filesystem type is also passed to the guest as
`kron.fs`.

The harness uses TCG explicitly; KVM is not required. A readable kernel can be
provided with `--kernel`. Otherwise it first checks local unprivileged paths,
then downloads the matching Ubuntu `linux-image-unsigned-$(uname -r)` package
with `apt-get download` and extracts it without installing anything.

If `/usr/bin/busybox` is not statically linked, the harness similarly downloads
and extracts Ubuntu's `busybox-static` package without installing it. The
matching readable `/boot/config-$(uname -r)` is inspected before boot:

- built-in virtio-blk uses `/dev/vda`;
- otherwise a built-in QEMU IDE/SCSI path uses `/dev/sda`;
- if ext4, XFS or Btrfs is a module, the matching `linux-modules-$(uname -r)`
  package is used when necessary; only the requested filesystem and its
  dependency closure are copied into the initramfs, decompressed, and loaded
  before mounting.

For a non-host kernel, pass its matching config with `--kernel-config`; kernel
and modules must have exactly matching release/ABI values.

The default QEMU `cache=writeback` setup honors guest flush requests and is a
real abrupt child-VM loss. It does not power off the host storage: unflushed
writes may still reach the host backing file through the host page cache.
Therefore the sound gate assertion is that all acknowledged sequences survive;
it must not assert that every unacknowledged sequence is absent.

## Verified pilot

`zig build powerloss-writer -Doptimize=ReleaseSafe` builds the actual Runtime,
FileSink and Journal test executable. Two independent child-VM runs completed
with ACK 1 and ACK 3 on Linux 6.8/ext4. Both verifier boots confirmed every
acknowledged JSON record and a durable checkpoint at the acknowledged sequence.

Compact transcripts and binary/image identities are preserved in
[the pilot results](evidence/2026-10-31/results.json). Original 128 MiB scratch
images remain in the evidence paths recorded there; they are not packaged with
the library. The harness verified the base-image hash before/after the snapshot
verification boot. This pilot is evidence for those exact runs, not a blanket
hardware durability guarantee or a randomized failure campaign.

`campaign.py` repeats the actual child-VM loss across selected acknowledgement
boundaries, including sequences beyond the journal ring capacity. The
[four-trial campaign](evidence/2026-10-31-campaign/README.md) passed ACK17/31/8/3.
It uses fresh scratch images and refuses to overwrite existing evidence.

The XFS path was exercised with a 512 MiB image: a single non-schema ACK1 run
and a four-trial schema campaign passed ACK17/31/8/3, and the ext4 path was
rechecked after the harness change. See
[the XFS campaign report](../../bench/evidence/2026-11-03-powerloss-xfs/README.md).
Btrfs was exercised the same way (single ACK1 and four-trial schema campaign
ACK17/31/8/3); see
[the Btrfs campaign report](../../bench/evidence/2026-11-03-powerloss-btrfs/README.md).
F2FS was exercised on a 128 MiB image (single ACK1 and four-trial schema
campaign ACK17/31/8/3); see
[the F2FS campaign report](../../bench/evidence/2026-11-03-powerloss-f2fs/README.md).
