# Fresh Linux mmap只写header初始化

**本轮优化已保留。** 基线`19f7f56`。Fresh mmap此前对整段映射执行`@memset`，并在`Mapping.open`逐页写同一字节，导致所有页变脏，随后publication/fsync需要回写整个journal。候选只在平台能证明fresh extents读为零时使用header-only初始化；未知文件系统继续完整清零。

## 改动边界

- Linux backend新增`freshZeroed(file)`，仅对ext4/ext2/3 magic `0xef53`、XFS `0x58465342`、btrfs `0x9123683e`、F2FS `0xf2f52010`返回true；未知文件系统返回false。
- `Mapping`保存`fresh_zeroed`；fresh file在`setLength`+`fallocate`后查询该能力。
- Linux `map`已有`MAP_POPULATE`，跳过generic逐页写；Windows/Darwin仍执行prefault，但改为volatile read，避免无谓dirty页。非Linux `freshZeroed`返回false，继续完整`@memset`。
- `Storage.freshIsZeroed()`对memory返回true、mapped返回平台结论；`Journal.createWithMode`据此选择`initializeZeroed`/`initializeV2Zeroed`。
- 非fresh文件仍走validate/recovery；file publication、目录fsync、CRC、slot/generation和错误路径不变。

## zero契约

`fresh_zero_probe.py`在当前仓库ext4上创建16MiB新文件，以及写入4KiB后truncate到0再扩展的文件；`setLength`+`posix_fallocate`后读取全部bytes：

| 场景 | size | nonzero bytes |
| --- | ---: | ---: |
| new | 16,777,216 | 0 |
| truncated | 16,777,216 | 0 |

两个文件sha256均为`080acf35a507ac9849cfcba47dc2ad83e01b75663a516279c8b9d243b719643e`。这只证明当前ext4窗口；其他文件系统必须命中白名单才走fast path，否则完整清零。

## 正确性

- 现有journal roundtrip、mmap恢复、schema、CRC、真实SIGKILL和平台对象测试全部执行。
- 新增`fresh mapped zero capability implies zero body`测试：平台报告`fresh_zeroed`时检查新映射body全零；非白名单/非支持平台skip。
- Debug与ReleaseFast测试通过。
- ReleaseSafe完整门禁151/151步骤、642/643项通过（1项系统local能力skip），包含源码分发、九目标对象、真实SIGKILL、单线程、时间oracle与全部示例；日志中的compression/tsc诊断带Zig build的“failed command”字样，但对应step success、整个命令exit0。
- 未做Windows/macOS/Android/iOS设备运行声明；这些平台继续完整清零，只有prefault读替换。

## 初始化测量

`mmap_init_probe.py`用async Mmap、file sink、256槽、`max-record-bytes=65536`（约16.8MB journal），1000事件+100 warmup；每进程分别报告sampled/batch runtime init。5对交替before/after，CPU0/2/4/6/8/10，work-dir使用当前ext4。

| phase | before中位 | after中位 | 比值 | 5对方向 |
| --- | ---: | ---: | ---: | --- |
| sampled | 54.212ms | 8.227ms | 0.152 | 5/5下降（0.128–0.235） |
| batch | 53.809ms | 6.948ms | 0.129 | 5/5下降（0.118–0.202） |

两组bootstrap中位区间均不重叠；before的spread超过10%门限，因此stable标志仍为false，但方向和幅度在全部5对一致。512B小队列（约147KB）中位0.945/0.961，区间重叠，差异低于宿主噪声，不据此宣称小队列收益。

该结果只证明fresh mmap初始化局部成本下降，不代表producer/consumer吞吐、Mmap稳态、durable或跨库排名。原始20项/phase、全部命令/stdout/stderr与source/binary身份见本目录。

## 复现

```sh
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseFast
zig build verify-local check-platforms test-package-distribution test-logging -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/evidence/2026-11-02-mmap-fresh-zero-init/fresh_zero_probe.py
python3 bench/evidence/2026-11-02-mmap-fresh-zero-init/mmap_init_probe.py --record-bytes=65536 --capture-name=large-64k
python3 bench/evidence/2026-11-02-mmap-fresh-zero-init/mmap_init_probe.py --record-bytes=512 --capture-name=small-512
```

`before-provenance.json`固定`19f7f56`源码/二进制，`after-provenance.json`固定候选；两个source archive保留拥有文件。脚本拒绝覆盖已有捕获，复跑前应复制到新的evidence目录。
