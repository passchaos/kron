# XFS child-VM abrupt loss campaign

在已有ext4 QEMU gate之后增加XFS路径，验证同一Runtime/FileSink/Journal在XFS上于durable ACK边界被SIGKILL后，已确认记录与checkpoint仍可在第二boot恢复。仍是child-VM突发终止，不是host物理掉电。

## Harness改动

- `vm_powerloss.py`新增`--filesystem ext4|xfs`；guest通过`kron.fs`选择`mount -t`，ext4保留`data=ordered`，XFS使用默认选项。
- 模块闭包从硬编码ext4改为按filesystem选择`CONFIG_EXT4_FS`/`CONFIG_XFS_FS`，只把请求文件系统及依赖closure放入initramfs。
- XFS镜像至少512MiB（mkfs.xfs拒绝≤300MiB）；host无`mkfs.xfs`时用`apt-get download xfsprogs`+`dpkg-deb -x`提取，不安装。
- `campaign.py`新增`--filesystem`并记录到results；ext4路径保持原128MiB与e2fsck只读诊断，XFS不跑e2fsck。

## 身份

- 源码：提交`d048f15`加本轮harness改动（未改生产src）。
- writer：`ac1960443590a075019a9aca41c54857fb7b78f5ef5fe8eb24798993030f5058`（`zig build powerloss-writer -Doptimize=ReleaseSafe`）。
- kernel：Ubuntu `linux-image-unsigned-6.8.0-147-generic`，`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- XFS modules：`libcrc32c.ko` `59075d7ce1ff1bbaaaaf81580970c59235d23f35c90ad3fec5f21c35e6551393`、`xfs.ko` `de0a1be386118221ac3790296fe9f421ba30b4fdacf997d2cc9837e4747e2f27`。
- xfsprogs deb：`xfsprogs_6.6.0-1ubuntu2.1_amd64.deb`，`2da65187043b2f8739f68d919faec7c1a4c172804c6a7cd6d816e02dd941bc71`。
- QEMU TCG、`cache=writeback`、`-snapshot` verify boot；512MiB scratch。

## 结果

- 单次非schema：`KRON_ACK seq=1`、`KRON_CHECKPOINT_OK seq=1`、`KRON_VERIFY_OK acked=1`，PASS。见[single-run-writer.log](single-run-writer.log)与[single-run-verify.log](single-run-verify.log)。
- schema campaign 4/4通过，ACK 17/31/8/3；每次verify确认最高generation checkpoint、journal/output high-water mark与通过ACK的完整JSON。crash image SHA-256：

| ACK | crash image SHA-256 |
| ---: | --- |
| 17 | `b8696842ef541364992e3013769f382979802adf8e09828114d548aa306cc9f0` |
| 31 | `20597989990709edf637d7ebf7f35c8d692dd894574d1758b003dfa49f44a524` |
| 8 | `5f41cb1a7cc6ec9e7c3775bdbc07685a2242120c963d9d50dd2b61663c2c81ae` |
| 3 | `10d0dc28261ec33a99398214f33f5e766fa869f9550ca64092a9852ff5ebccf1` |

完整机器可读结果见[results.json](results.json)，逐run串口输出见[run-00.log](run-00.log)、[run-01.log](run-01.log)、[run-02.log](run-02.log)、[run-03.log](run-03.log)与[campaign.log](campaign.log)。

- Harness改动后的ext4回归单次ACK1仍PASS，见[ext4-regression.log](ext4-regression.log)。

## 边界

这是XFS child-VM SIGKILL，不是物理host掉电；`cache=writeback`下未flush写入仍可能经host page cache到达backing file，因此只断言已确认序列存活。没有Btrfs/F2FS/NFS/真实设备系统停机，没有跨平台旧二进制；XFS镜像512MiB，与ext4的128MiB不同。整体“业界最佳”目标仍未完成。
