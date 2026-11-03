# F2FS child-VM abrupt loss campaign

在ext4/XFS/Btrfs之后继续扩展QEMU child-VM abrupt-loss gate到F2FS，验证同一Runtime/FileSink/Journal在F2FS上于durable ACK边界被SIGKILL后，已确认记录与checkpoint仍可在第二boot恢复。仍是child-VM突发终止，不是host物理掉电。

## Harness

- `vm_powerloss.py`/`campaign.py`的`--filesystem`现支持`ext4|xfs|btrfs|f2fs`；guest通过`kron.fs`选择`mount -t`，ext4保留`data=ordered`，其他文件系统使用默认选项。
- F2FS模块闭包为`crc32_generic`、`lz4hc_compress`、`lz4_compress`、`f2fs`。**`crc32_generic`不是`modules.dep`中f2fs.ko的依赖**：首次只加载modules.dep closure时guest报告`F2FS-fs (vda): Cannot load crc32 driver.`；harness现为f2fs显式追加该crypto provider。
- host无`mkfs.f2fs`时用`apt-get download f2fs-tools`+`dpkg-deb -x`提取；f2fs使用`-l`标签选项（xfs/btrfs使用`-L`）。
- 镜像128MiB；ext4仍保留e2fsck只读诊断，其他文件系统不跑e2fsck。

## 身份

- 源码：提交`db4f317`加本轮F2FS harness改动（未改生产src）。
- writer：`ac1960443590a075019a9aca41c54857fb7b78f5ef5fe8eb24798993030f5058`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- modules：`crc32_generic.ko` `5dc5f650ff80a6372ecb77c1c01d5df5055171ab55ddc75d4617102199adcafb`、`lz4hc_compress.ko` `ec57cbd7fc6394b33fe008563a91bffb054cd46551f4f40a2002448989747154`、`lz4_compress.ko` `4a6c9aba65642b91581a138d37ac1d959cd04309d4ac7ec5249a3617b135deaa`、`f2fs.ko` `fbf38067a4672916bae005821b0cbaf47a7082c5a37951454ede2ec296bd5911`。
- f2fs-tools deb：`f2fs-tools_1.16.0-1_amd64.deb`，`914097c27d98f03e5fe56c5038e1a5abd81b8cbf0b24132fa234d608dfa60ea3`。
- QEMU TCG、`cache=writeback`、`-snapshot` verify boot；128MiB scratch。

## 结果

- 单次非schema：`KRON_ACK seq=1`、`KRON_CHECKPOINT_OK seq=1`、`KRON_VERIFY_OK acked=1`，PASS。见[single-run-writer.log](single-run-writer.log)与[single-run-verify.log](single-run-verify.log)。
- schema campaign 4/4通过，ACK 17/31/8/3；每次verify确认最高generation checkpoint、journal/output high-water mark与通过ACK的完整JSON。crash image SHA-256：

| ACK | crash image SHA-256 |
| ---: | --- |
| 17 | `2e57ee9cc41e2f134ec0da0d45a3024992b29fe8c78444ff4cf673ee36520af6` |
| 31 | `ec7aa48fd6344a1f629e89b926f1bc6abbf138cc192435939639eaa54fd259b0` |
| 8 | `f6a66167e644715342cce571c2e62288aaef4254eedcff649d083fd96c7b5494` |
| 3 | `99966d5f24107a79d2c63668a977e0c95465a296518137682ad94a0e5f9a06d9` |

完整机器可读结果见[results.json](results.json)，逐run串口输出见[run-00.log](run-00.log)、[run-01.log](run-01.log)、[run-02.log](run-02.log)、[run-03.log](run-03.log)与[campaign.log](campaign.log)。

## 边界

这是F2FS child-VM SIGKILL，不是物理host掉电；`cache=writeback`下未flush写入仍可能经host page cache到达backing file，因此只断言已确认序列存活。没有NFS/真实设备系统停机，没有跨平台旧二进制。整体“业界最佳”目标仍未完成。
