# 只读文件系统初始化故障测试

在child VM内以只读方式挂载ext4 image，尝试创建FileSink与mmap Journal，验证两者都以`ReadOnlyFileSystem`拒绝，不会误报初始化成功。

## Harness

- `tests/faults/vm_readonly.py`：复用`tests/power_loss`的kernel/busybox/initramfs构建，创建64MiB ext4 image，QEMU `-drive ...,readonly=on`，guest以`mount -t ext4 -o ro,data=ordered`挂载到`/mnt`。
- `testwriter readonly`：分别尝试`FileSink.create`与`Journal.create`；任一成功都会打印`UNEXPECTED`并失败，拒绝则打印`KRON_READONLY_FILE_REJECTED`/`KRON_READONLY_JOURNAL_REJECTED`。
- 只读image由QEMU与guest mount共同保证；host不挂载image。

## 身份

- 源码：提交`183b1c9`加本轮testwriter/harness改动（未改生产src）。
- writer：`3fd3bf6f4417bffd66ed318fcd4fe5c1f36787aa74649abd3ffcd6df2800d40b`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- ext4 64MiB、QEMU TCG、`readonly=on`。

## 结果

```
KRON_READONLY_FILE_REJECTED err=ReadOnlyFileSystem
KRON_READONLY_JOURNAL_REJECTED err=ReadOnlyFileSystem
KRON_READONLY_RC=0
```

- FileSink与mmap Journal都在初始化阶段返回`error.ReadOnlyFileSystem`，没有创建/截断成功路径。
- 原始输出见[serial.log](serial.log)与[run.log](run.log)。

## 边界

只读挂载不是掉电、crash或durable资格；没有覆盖只读文件系统上的recovery、多文件系统或设备。整体“业界最佳”目标仍未完成。
