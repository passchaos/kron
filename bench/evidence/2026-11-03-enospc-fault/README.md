# 真实ENOSPC FileSink故障测试

在child VM内挂载1MiB tmpfs，先让FileSink缓冲一条记录，再用另一个文件填满tmpfs，最后flush。验证真实`NoSpaceLeft`会从FileSink错误路径返回并latch，不会产生成功的durable确认。

## Harness

- `tests/faults/vm_enospc.py`：复用`tests/power_loss`的kernel/busybox/initramfs构建，guest挂载`tmpfs size=1M`，运行`/bin/testwriter enospc --journal /mnt/kron.journal --output /mnt/kron.log`。
- `testwriter enospc`：创建portable `FileSink`并缓冲`buffered-before-full\n`；创建`kron.log.filler`，以4KiB positional write循环到`NoSpaceLeft`；随后`FileSink.flush()`必须返回错误并打印`KRON_ENOSPC_LATCHED`。若flush成功则打印`KRON_ENOSPC_UNEXPECTED`并失败。
- QEMU TCG，无磁盘/无9p；tmpfs在guest内，不涉及host文件系统。

## 身份

- 源码：提交`84ae279`加本轮testwriter/harness改动（未改生产src）。
- writer：`6af1812b9cd6617097368685611bf2569fda246d4b047a84874d81908ce5be3e`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。

## 结果

```
KRON_ENOSPC_FILLED bytes=1048576
KRON_ENOSPC_LATCHED err=NoSpaceLeft
KRON_ENOSPC_RC=0
```

- 1,048,576B填满1MiB tmpfs后，FileSink flush返回`error.NoSpaceLeft`并latch；testwriter以成功状态退出，表示错误被正确观察，而不是误报写出成功。
- 原始输出见[serial.log](serial.log)与[run.log](run.log)。

## 边界

tmpfs是volatile文件系统；本测试不涉及mmap journal、recovery、durable ACK、掉电或多文件系统。它补充真实ENOSPC文件写错误路径，不替代crash/power-loss资格。整体“业界最佳”目标仍未完成。
