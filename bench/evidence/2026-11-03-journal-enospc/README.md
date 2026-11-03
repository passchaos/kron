# Journal ENOSPC预分配拒绝测试

在child VM内用64MiB ext4 image，先以4KiB positional write填满到`NoSpaceLeft`，再尝试创建可恢复mmap Journal。验证Journal初始化在无空间时返回`NoSpaceLeft`，不会误报成功或创建半初始化journal。

## Harness

- `tests/faults/vm_journal_enospc.py`：复用`tests/power_loss`的kernel/busybox/initramfs构建，创建64MiB ext4 image，guest以rw挂载`/mnt`。
- `testwriter journal-enospc`：创建`/mnt/kron.journal.filler`并写到`NoSpaceLeft`，打印`KRON_JOURNAL_ENOSPC_FILLED`；随后`Journal.create`（capacity 16、max_record 2048）；成功则打印`UNEXPECTED`并失败，拒绝则打印`KRON_JOURNAL_ENOSPC_REJECTED`。
- QEMU TCG，无snapshot；host不挂载image。

## 身份

- 源码：提交`22f8547`加本轮testwriter/harness改动（未改生产src）。
- writer：`1e05c66072a636f4d5ad05320758c5e4a564f51858c16e9369df71baba52dfae`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。
- ext4 64MiB、QEMU TCG、`cache=writeback`。

## 结果

```
KRON_JOURNAL_ENOSPC_FILLED bytes=57311232
KRON_JOURNAL_ENOSPC_REJECTED err=NoSpaceLeft
KRON_JOURNAL_ENOSPC_RC=0
```

- 填满约57MB后，Journal预分配返回`error.NoSpaceLeft`；没有成功创建或误报初始化完成。
- 原始输出见[serial.log](serial.log)与[run.log](run.log)。

## 边界

该测试只覆盖journal初始化预分配失败，不涉及crash/recovery/durable ACK、物理掉电或多文件系统。整体“业界最佳”目标仍未完成。
