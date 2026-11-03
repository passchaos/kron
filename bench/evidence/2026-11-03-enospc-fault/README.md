# 真实ENOSPC FileSink/Runtime/Rolling故障测试

在child VM内挂载1MiB tmpfs，覆盖三条真实`NoSpaceLeft`路径：直接FileSink在缓冲后填满再flush；Runtime（Memory queue + FileSink）在填满后提交记录再`flush(.durable)`；RollingFileSink在缓冲后填满再flush。三者都必须返回错误并latch，不能误报成功。

## Harness

- `tests/faults/vm_enospc.py`：复用`tests/power_loss`的kernel/busybox/initramfs构建，guest挂载`tmpfs size=1M`，运行`/bin/testwriter enospc --journal /mnt/kron.journal --output /mnt/kron.log`。
- `testwriter enospc`：
  1. 创建portable `FileSink`并缓冲`buffered-before-full\n`；
  2. 创建Runtime（Memory queue `capacity=8`、FileSink route、JSON）；
  3. 创建RollingFileSink（64KiB max、retention 2）并缓冲`rolling-before-full\n`；
  4. 创建`kron.log.filler`，以4KiB positional write循环到`NoSpaceLeft`；
  5. 直接`FileSink.flush()`必须返回错误并打印`KRON_ENOSPC_LATCHED`；
  6. 填满后提交一条Runtime记录，`runtime.flush(.durable)`必须返回错误并打印`KRON_ENOSPC_RUNTIME_LATCHED`；
  7. `RollingFileSink.flush()`必须返回错误并打印`KRON_ENOSPC_ROLLING_LATCHED`。
- 任一flush成功都会打印`UNEXPECTED`并失败。
- QEMU TCG，无磁盘/无9p；tmpfs在guest内，不涉及host文件系统。

## 身份

- 源码：提交`84ae279`加本轮testwriter/harness改动（未改生产src）。
- writer：`ebb1a0bb20f0333e8d1bf9df8e3dcee654c3962b80400d3765d5b08e6a7cd47c`。
- kernel：`a02b7c02ade2b0e9c4dcac8144444276a8a2e0be61279a909cbf3f5d3fb0327b`。
- busybox：`dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14`。

## 结果

```
KRON_ENOSPC_FILLED bytes=1048576
KRON_ENOSPC_LATCHED err=NoSpaceLeft
KRON_ENOSPC_RUNTIME_LATCHED err=NoSpaceLeft
KRON_ENOSPC_ROLLING_LATCHED err=NoSpaceLeft
KRON_ENOSPC_RC=0
```

- 1,048,576B填满1MiB tmpfs后，直接FileSink flush返回`error.NoSpaceLeft`并latch。
- Runtime在填满后提交的记录同样在durable flush返回`error.NoSpaceLeft`并latch。
- RollingFileSink的缓冲记录同样在flush返回`error.NoSpaceLeft`并latch。
- testwriter以成功状态退出，表示错误被正确观察，而不是误报写出成功。
- 原始输出见[serial.log](serial.log)与[run.log](run.log)。

## 边界

tmpfs是volatile文件系统；Runtime使用Memory queue + FileSink，RollingFileSink为独立路径；不涉及mmap journal、recovery、durable ACK、掉电或多文件系统。它补充真实ENOSPC文件写错误路径，不替代crash/power-loss资格。整体“业界最佳”目标仍未完成。

