# Memory journal单次清零初始化

**本轮优化已保留。** 基线`89f0510`。Memory journal的`Storage.createMemory`已经完整清零并writable-touch映射；随后`format.initialize`/`initializeV2`又对同一段内存执行一次完整`@memset`，原`Storage.createMemory`还逐页重复写0。候选删除逐页循环，并让memory路径使用只写header/checkpoint的`initializeZeroed`/`initializeV2Zeroed`；file映射继续使用完整清零入口，避免复用映射中的旧字节被当成有效slot payload。

## 改动边界

- `Storage.createMemory`保留唯一一次完整`@memset`，删除每4096字节的volatile写0循环。
- `format.initializeZeroed`/`initializeV2Zeroed`复用已清零buffer，只写magic/version/layout/identity/header CRC/checkpoint；`initialize`/`initializeV2`仍先完整清零，file路径不变。
- `Journal.createWithMode`只在`memory` backing为fresh时选择zeroed入口；mmap/file、schema extension、recovery、CRC、slot/generation和所有错误路径不变。
- 新增format测试用0xa5填充的完整清零结果与zeroed结果逐字节比较，覆盖v1/v2。

## 正确性

- 新增`zeroed initialization matches full clear for memory-backed journals`。
- `zig build test -Doptimize=Debug`与`-Doptimize=ReleaseFast`通过。
- ReleaseSafe完整门禁151/151步骤、641/642项通过（1项系统local能力skip），包含源码分发、九目标对象、真实SIGKILL、单线程、时间oracle与全部示例；日志中的compression/tsc诊断带Zig build的“failed command”字样，但对应step success、整个命令exit0。

## 大队列初始化

`init_probe.py`用`--mode=async --storage=memory --sink=file --journal-slots=256 --max-record-bytes=65536`，即约16.8MB journal，1000事件+100 warmup；每进程分别报告sampled/batch两个runtime init。5对交替before/after，CPU0/2/4/6/8/10，逐项记录source/binary身份。

| phase | before中位 | after中位 | 比值 | 5对方向 |
| --- | ---: | ---: | ---: | --- |
| sampled | 10.793ms | 6.992ms | 0.648 | 4/5下降，1对约1.009 |
| batch | 9.130ms | 6.638ms | 0.727 | 5/5下降（0.565–0.739） |

batch的before/after bootstrap中位区间不重叠；sampled中位下降但区间仍重叠，属于高负载窗口下的局部测量。原始20项/phase在`large-64k-results.jsonl`，全部命令与stdout/stderr在`large-64k-trials/`。

## 小队列控制

同脚本`--max-record-bytes=512`（约147KB journal）5对结果方向混合，sampled/batch中位比值1.299/1.369但区间全部重叠。该规模下省去的清零工作远小于宿主噪声，不能据此宣称回归或收益；保留原始数据仅作控制。见`small-512-results.jsonl`/`small-512-comparison.json`。

## 采纳与复现

采纳依据是memory路径确实从多次完整清零降为一次、file路径语义不变、v1/v2字节对照和完整门禁通过，以及16.8MB journal的batch初始化5/5下降、中位区间不重叠。该结果只证明初始化局部成本，不代表producer/consumer吞吐、Mmap启动或跨库排名。

```sh
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseFast
zig build verify-local check-platforms test-package-distribution test-logging -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/evidence/2026-11-02-memory-init-zeroing/init_probe.py --record-bytes=65536 --capture-name=large-64k
python3 bench/evidence/2026-11-02-memory-init-zeroing/init_probe.py --record-bytes=512 --capture-name=small-512
```

`before-provenance.json`固定`89f0510`源码/二进制，`after-provenance.json`固定候选；两个source archive保留拥有文件。脚本拒绝覆盖已有捕获，复跑前应复制到新的evidence目录。
