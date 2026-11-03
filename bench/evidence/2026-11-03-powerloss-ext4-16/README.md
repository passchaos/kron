# ext4 16-trial child-VM abrupt-loss campaign

在V3 schema journal的4-run campaign之后，用同一gate扩展到16个ACK边界，覆盖更多ring复用位置与随机ACK序列。仍是child-VM SIGKILL，不是host物理掉电。

## 身份

- 源码：提交`17eb612`加本轮testwriter/harness改动（未改生产src）。
- writer：`ebb1a0bb20f0333e8d1bf9df8e3dcee654c3962b80400d3765d5b08e6a7cd47c`（`zig build powerloss-writer -Doptimize=ReleaseSafe`）。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- ext4 128MiB、QEMU TCG、`cache=writeback`、`-snapshot` verify boot、campaign seed `0x4B524F4E`。

## 结果

16/16通过；ACK边界为：

`17, 31, 8, 3, 9, 40, 63, 59, 14, 23, 29, 19, 13, 57, 37, 14`

每次verify确认最高generation checkpoint、journal/output high-water mark与通过ACK的完整JSON。crash image SHA-256前缀：

| run | ACK | pass | crash image |
| ---: | ---: | --- | --- |
| 0 | 17 | yes | `2d7b520a5d5f063c…` |
| 1 | 31 | yes | `f6adb8b12a3f1002…` |
| 2 | 8 | yes | `68e584ac1f7e6616…` |
| 3 | 3 | yes | `a51d2e7496db29d2…` |
| 4 | 9 | yes | `fc275a9d447ebaef…` |
| 5 | 40 | yes | `4507351f5851642b…` |
| 6 | 63 | yes | `ad43f763f876f371…` |
| 7 | 59 | yes | `6d56bf5bcd115c76…` |
| 8 | 14 | yes | `8ac9ddf3f8ce1739…` |
| 9 | 23 | yes | `0873a82afd5894b8…` |
| 10 | 29 | yes | `cfbcfadc4fe874d7…` |
| 11 | 19 | yes | `9d52808b375a4fad…` |
| 12 | 13 | yes | `54e833705630a2b3…` |
| 13 | 57 | yes | `728d260f2ae412ad…` |
| 14 | 37 | yes | `9d33209a68e32f83…` |
| 15 | 14 | yes | `df1a0cd398837993…` |

完整机器可读结果与逐run命令见[results.json](results.json)，串口输出见`run-00.log`…`run-15.log`与[campaign.log](campaign.log)。

## 边界

这是ext4 child-VM SIGKILL；`cache=writeback`下未flush写入仍可能经host page cache到达backing file，因此只断言已确认序列存活。没有物理掉电、XFS/Btrfs/F2FS之外的NFS/CIFS/FUSE或真实设备资格。整体“业界最佳”目标仍未完成。
