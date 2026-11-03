# 9p共享文件系统行为

通过QEMU `-virtfs`把host目录作为virtio-9p共享给child VM，运行public package consumer的五个模式和`qualify`，补充network/shared文件系统行为。不是crash、掉电或NFS资格。

## Harness

- `tests/shared_fs/vm_9p.py`：复用`tests/power_loss`的kernel/busybox/initramfs构建，加载`9p`/`9pnet`/`9pnet_virtio`/`netfs`模块，guest以`trans=virtio,version=9p2000.L,msize=131072`挂载`hostshare`。
- QEMU TCG、无磁盘image；host share只在guest内挂载，host侧只读取生成文件。
- 每个mode单独boot，guest运行`/bin/testwriter <mode> /mnt/<mode>`或`qualify`，打印JSON与`KRON_9P_RC`。

## 身份

- 源码：提交`b5f63ca`加本轮`tests/shared_fs`（未改生产src）。
- consumer：native static x86-64 package consumer，`5f5c0ca69a0713a1b41865026c737617c53fde6e7cded286ad00f72b27ea6dcc`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- 9p modules：`9pnet` `e7cd70ad...`、`netfs` `8246bf91...`、`9p` `e0a621ec...`、`9pnet_virtio` `8a40b0cf...`（完整hash见[share-files.txt](share-files.txt)与串口日志）。

## 结果

| mode | 结果 |
| --- | --- |
| sync | accepted=written=2、pending=0 |
| memory | accepted=written=2、pending=0 |
| spsc_memory | accepted=written=2、pending=0 |
| mmap | **拒绝`PreallocationUnsupported`** |
| spsc_mmap | **拒绝`PreallocationUnsupported`** |
| qualify | **拒绝`PreallocationUnsupported`**（在mmap路径） |

host share中sync/memory/spsc_memory生成有效JSON（约597–599B）；mmap/spsc_mmap留下70,656B journal文件与0B output，但没有任何成功记录；qualify只创建了`native-check`目录。完整文件清单见[share-files.txt](share-files.txt)，逐mode串口输出见[sync-serial.log](sync-serial.log)、[memory-serial.log](memory-serial.log)、[spsc_memory-serial.log](spsc_memory-serial.log)、[mmap-serial.log](mmap-serial.log)、[spsc_mmap-serial.log](spsc_mmap-serial.log)与[qualify-serial.log](qualify-serial.log)。

## 机制与决策

9p不提供`fallocate`/预分配语义；`Journal`/mapping在创建可恢复mmap journal时返回`error.PreallocationUnsupported`，因此不会把未预分配的文件当作可恢复journal继续使用。Sync/Memory路径不依赖mmap journal，继续工作。生产代码无需改动；该行为已由现有错误路径保证。

## 边界

9p不是NFS，也不是本地块设备；本测试没有crash、掉电、durable flush资格，也没有验证9p的cache/coherency语义。没有XFS/Btrfs/F2FS以外的NFS/CIFS/FUSE或真实设备。整体“业界最佳”目标仍未完成。
