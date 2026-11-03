# P1 text-mmap producer profile

## 身份与命令

- binary `75ea869...`/text-mmap（[binary.sha256](binary.sha256)），源码提交`4ace0fe`。
- `taskset -c 16,18,20,22,24,26 reference-kron --events=100000 --warmup=1000 --producers=1 --phase=batch --queue-slots=256 --frontend=managed --mode=async --storage=mmap --schema=false --text-format=true`
- `perf record -e cpu_atom/cycles/u -g`；397 samples、2.364亿 cycles；host load见[host-load.txt](host-load.txt)。

## 结果

单trial的cycles自占（`--no-children`）：

| 符号 | 占总cycles | 归属 |
| --- | ---: | --- |
| `memcpyFast` | 11.25% | producer render 4.44%、FileSink write 4.24%、jsonMember 1.94% |
| `Runtime.submitSafeDestination` | 10.48% | producer |
| `Runtime.drainJournal` | 10.17% | consumer |
| `decimal.writeNative` | 7.52% | producer render |
| `Journal.reserve` | 4.94% | producer |
| `Runtime.begin` | 4.51% | producer |
| `codec.measure` | 4.38% | producer |
| `releaseWrittenRun` | 4.18% | consumer |
| `jsonMember` | 4.02% | producer render |
| `renderWithTime` | 3.76% | producer render |
| `Worker.emit` | 3.65% | producer |

producer约43%总cycles：render（renderWithTime+decimal+jsonMember+memcpy约20%）、submit 10.5%、reserve 4.9%、begin 4.5%、measure 4.4%。consumer约18.5%：drainJournal 10.2%、FileSink 4.2%、release 4.2%。

## 解释与下一步

P1 text-mmap是producer-limited。journal ring的`reserve`约5%，但更大成本是admission/`begin`、`codec.measure`与render本身；consumer的同步FileSink写约4%。tracing mmap P1 2.4M–2.97M vs kron 2.03M–2.30M的差距来自：

1. tracing producer只做format+enqueue，没有kron的admission/measure/journal；
2. tracing mmap backend的writer/刷新与producer重叠。

只做轻量text ring（省reserve约5%）不足以补齐约22%差距。要真正超过P1 tracing mmap，需要独立的**dedicated fast logger**（跳过admission/measure/journal，producer format+ring push）或**mmap output backend**（writer与producer重叠），并保持默认durable路径不变。

该profile只用于定位下一候选，不是速度排名；原始perf数据见[perf.data.xz](perf.data.xz)，完整报告见[report.txt](report.txt)。
