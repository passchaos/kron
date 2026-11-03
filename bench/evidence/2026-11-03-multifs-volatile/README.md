# tmpfs vs ext4多文件系统行为

补充不同文件系统上的public package consumer行为：tmpfs上Memory/Sync可写，mmap journal按设计以`VolatileFilesystem`拒绝；ext4上五模式全部通过。

## 身份

- 源码：提交`5df4c6c0d1855b5f36f06b2272990dba6771ee3b`。
- consumer：native x86-64 static ReleaseSafe，`5f5c0ca69a0713a1b41865026c737617c53fde6e7cded286ad00f72b27ea6dcc`。
- 文件系统：`/dev/shm`为tmpfs；`/tmp`由`df -T`报告ext4（`stat -f`显示ext2/ext3 family）。
- 运行：同一binary、同一五模式、同一输出/attributes核对逻辑，仅输出根目录不同。

## 结果

| mode | tmpfs `/dev/shm` | ext4 `/tmp` |
| --- | --- | --- |
| sync | 2 records, pending=0 | 2 records, pending=0 |
| memory | 2 records, pending=0 | 2 records, pending=0 |
| mmap | **`VolatileFilesystem`拒绝** | 2 records, pending=0, 1 journal |
| spsc_memory | 2 records, pending=0 | 2 records, pending=0 |
| spsc_mmap | **`VolatileFilesystem`拒绝** | 2 records, pending=0, 2 journals |

tmpfs拒绝发生在创建阶段，目录中仅留下0字节的`events.journal`/`events.jsonl`，没有记录或journal header；这与文档“初始化失败不恢复已创建/截断文件内容”的边界一致。ext4对照组逐条核对JSON attributes、nested/redaction与journal `KRONJNL1` header。原始输出见[run.log](run.log)。

## 机制

`src/platform/mapping/linux.zig`读取statfs类型，tmpfs（`0x01021994`）与ramfs（`0x858458f6`）返回`error.VolatileFilesystem`，避免把volatile memory文件系统当作可恢复journal存储。Sync/Memory路径不使用mmap journal，因此在tmpfs上继续工作。

## 边界

这是两种文件系统的行为对照，不是多文件系统crash/掉电资格：没有真实设备、系统停机、物理掉电、XFS/Btrfs/F2FS或NFS；tmpfs本身不提供durable语义。没有性能测量或Foundation排名更新。整体“业界最佳”目标仍未完成。
