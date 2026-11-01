# Linux Mmap 初始化与 schema 发布

Linux/Android 的冷发布通过全文件 `fsync`，再同步父目录。Linux 内核的 `msync(MS_SYNC)` 调用 `vfs_fsync_range`；`fsync` 调用同一文件系统操作，范围为整个文件，并包含文件元数据。因此冷发布先 `msync` 再 `fsync` 会重复等待相同映射数据写回。

`platform.Mapping.publish` 在 Linux/Android 省去前面的 `msync`，保留全文件 `fsync` 和父目录 `fsync`。其他平台保留映射 flush 与文件发布的原顺序。显式 `Mapping.syncFile/sync`、journal durable checkpoint 和 durable reclaim 仍保持原映射、文件与目录同步协议。初始化继续执行文件预分配与可写页触碰，文件格式和资源预算没有变化。

这是 Linux 的文件同步契约，不能推广为所有平台的映射 flush 等价性。源码依据来自 Linux v6.8 的 `mm/msync.c`、`fs/sync.c` 和 `fs/ext4/fsync.c`，包括范围写回、文件系统 journal 提交、设备 flush 和回写错误处理。所读源码的 URL、SHA256 与相关片段保存在 `bench/evidence/2026-11-01-mmap-publication/`。

初始化的文件或目录 `fsync` 失败会向调用方返回错误，并释放映射与独占文件锁。schema 发布中，即使文件同步成功，目录同步失败也保持 descriptor 未就绪；producer 不能 reserve 引用该 schema 的记录，成功重试后才发布 ready。已有 failed-sync/reopen 资格继续执行。

静态 ReleaseSafe writer 已通过 Linux 6.8/ext4 子 QEMU 强杀验证：schema ACK17/31 和普通 inline ACK3 后恢复，每条已确认 JSON 与 checkpoint 保留，snapshot 验证没有改变原始镜像。这些是指定虚拟机、文件系统和确认点的证据；其他平台和设备资格仍按主验收清单推进。

真实 SPSC 四 producer 初始化的调用数由五次 `msync`、十次文件/目录 `fsync`，变为零次 `msync`、十次 `fsync`；五次预分配不变。160 次完整 Memory/Mmap、shared/SPSC、P1/P4 文件试验逐条核对 1616 万条 JSON。启动与吞吐全部因波动标 `inconclusive`，共享 Mmap 的初始化出现较慢中位，SPSC Mmap 的初始化中位下降，全部慢值保留。此修改减少重复同步调用，尚未取得稳定冷启动或吞吐提升资格。

完整输入、各阶段时间、调用分位数、文件 hash、失败与恢复记录见[验收报告](../bench/evidence/2026-11-01-mmap-publication/README.md)。后续对 Foundation 的性能判断仍需用当前源码同轮复测，不能把这项局部变化叠加到较早的排名。
