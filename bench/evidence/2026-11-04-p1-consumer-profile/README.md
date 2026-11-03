# P1 consumer profile after render cache

## 身份与命令

- binary `754d6a2...`（[binary.sha256](binary.sha256)），源码提交`97e47a0`/`7afc074`。
- `taskset -c 16,18,20,22,24,26 reference-kron --events=100000 --warmup=1000 --producers=1 --phase=batch --queue-slots=256 --frontend=managed --mode=async --storage=memory --schema=false`（cache默认关闭）。
- `perf record -e cpu_atom/cycles/u -g`；450 samples、2.711亿 cycles；host load见[host-load.txt](host-load.txt)。

## 结果

单trial的cycles自占（`--no-children`，不是吞吐资格）：

| 符号 | 占总cycles | 归属 |
| --- | ---: | --- |
| `Crc32.update` | 15.93% | consumer peek CRC 5.85% + release CRC 5.76% + producer 4.32% |
| `encodeJsonWithAttributes` | 10.15% | consumer render |
| `Runtime.submitSafeDestination` | 7.73% | producer |
| `decimal.writeNative` | 7.62% | consumer render |
| `memcpyFast` | 5.87% | producer encode 2.10%、sink 1.28%、render 1.15% |
| `jsonMember` | 4.96% | consumer render |
| `codec.encodeSized` | 4.45% | producer |
| `Runtime.begin` | 4.29% | producer |
| `Runtime.drainJournal` | 4.27% | consumer |
| `emitWireFused` | 3.31% | consumer |

P1的consumer路径约35%总cycles：JSON render（`encodeJsonWithAttributes`+decimal+jsonMember+memcpy约24%）与两次slot CRC（约11.6%）。producer侧为`begin`+`submitSafeDestination`+`encodeSized`+producer CRC约20%。

## 解释与下一步

P1下consumer是瓶颈；cache-on把render移到producer后producer成为瓶颈（约1.74M vs cache-off约1.9M），因此P1不能靠render cache解决。P1对tracing的差距（tracing约2.4M）来自tracing producer只做format+enqueue，而kron producer仍承担capture/encode/CRC/commit，consumer还要做deferred render与release CRC。

要同时保持默认CRC/三检查点/recovery并超过tracing P1，需要独立的**volatile text-queue fast mode**：producer capture+render+enqueue，consumer只写出，无journal/CRC/恢复；这与tracing同语义（无持久化），作为opt-in模式，不改变默认durable路径。该profile只用于定位下一候选，不是速度排名；原始perf数据见[perf.data.xz](perf.data.xz)，完整报告见[report.txt](report.txt)。
