# Btrfs child-VM abrupt loss campaign

在ext4与XFS之后继续扩展QEMU child-VM abrupt-loss gate到Btrfs，验证同一Runtime/FileSink/Journal在Btrfs上于durable ACK边界被SIGKILL后，已确认记录与checkpoint仍可在第二boot恢复。仍是child-VM突发终止，不是host物理掉电。

## Harness

- `vm_powerloss.py`/`campaign.py`的`--filesystem`现支持`ext4|xfs|btrfs`；guest通过`kron.fs`选择`mount -t`，ext4保留`data=ordered`，XFS/Btrfs使用默认选项。
- Btrfs模块闭包为`xor`、`raid6_pq`、`libcrc32c`、`btrfs`；只把这些模块放入initramfs。
- host无`mkfs.btrfs`时用`apt-get download btrfs-progs`+`dpkg-deb -x`提取，不安装。
- 镜像512MiB；ext4仍128MiB并保留e2fsck只读诊断，XFS/Btrfs不跑e2fsck。

## 身份

- 源码：提交`9447e9c`加本轮Btrfs harness改动（未改生产src）。
- writer：`ac1960443590a075019a9aca41c54857fb7b78f5ef5fe8eb24798993030f5058`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- modules：`xor.ko` `d998e45f782ed330de9ea68cffd75439826e2e2954dab81419e8ed1ec0695213`、`raid6_pq.ko` `6533ba1d296a45afae9991ef1edf481518b6651b2112d24042dfd5213c32526d`、`libcrc32c.ko` `59075d7ce1ff1bbaaaaf81580970c59235d23f35c90ad3fec5f21c35e6551393`、`btrfs.ko` `01c21f80c9d2a79dd4503e18ee333860f2d00284a465de0cd5c66901350c89f4`。
- btrfs-progs deb：`btrfs-progs_6.6.3-1.1build2_amd64.deb`，`b4aeb482adcce07b276827d8f4b0c502427a2a43574fa8349081f23dcd8c96aa`。
- QEMU TCG、`cache=writeback`、`-snapshot` verify boot；512MiB scratch。

## 结果

- 单次非schema：`KRON_ACK seq=1`、`KRON_CHECKPOINT_OK seq=1`、`KRON_VERIFY_OK acked=1`，PASS。见[single-run-writer.log](single-run-writer.log)与[single-run-verify.log](single-run-verify.log)。
- schema campaign 4/4通过，ACK 17/31/8/3；每次verify确认最高generation checkpoint、journal/output high-water mark与通过ACK的完整JSON。crash image SHA-256：

| ACK | crash image SHA-256 |
| ---: | --- |
| 17 | `e8a4f4b83b439256561bb5ad07041372bc518f35df859192d9a016ec56a79a59` |
| 31 | `f636f0254bf212ee0f7b7e378e96b7610ef9f9a216df928e63dfc3da3487abb3` |
| 8 | `b23f8daa336325a0b3e53c6bbceb3266eac4d29cc31aa7cfbe3d97c5848f25df` |
| 3 | `70676944a403371279e6a1042f3c4ef31969e080c040e1130869117cf6f658db` |

完整机器可读结果见[results.json](results.json)，逐run串口输出见[run-00.log](run-00.log)、[run-01.log](run-01.log)、[run-02.log](run-02.log)、[run-03.log](run-03.log)与[campaign.log](campaign.log)。

## 边界

这是Btrfs child-VM SIGKILL，不是物理host掉电；`cache=writeback`下未flush写入仍可能经host page cache到达backing file，因此只断言已确认序列存活。没有F2FS/NFS/真实设备系统停机，没有跨平台旧二进制；Btrfs/XFS镜像512MiB，与ext4的128MiB不同。整体“业界最佳”目标仍未完成。
