# 批量确认后的E-core consumer profile

## 身份与命令

- binary `1778caa...`（[binary.sha256](binary.sha256)），源码提交`e2934f8`。
- `taskset -c 16,18,20,22,24,26 reference-kron --events=100000 --warmup=1000 --producers=4 --phase=batch --queue-slots=256 --frontend=managed --mode=async --storage=mmap --schema=false`
- `perf record -e cpu_atom/cycles/u -g`；956 samples、4.448亿 cycles；host load见[host-load.txt](host-load.txt)。

## 结果

单trial的cycles自占（`--no-children`，不是吞吐资格）：

| 符号 | 占总cycles | 归属 |
| --- | ---: | --- |
| `Runtime.submitSafeDestination` | 13.69% | producer |
| `Crc32.update` | 10.39% | 其中consumer `validateSlot` 4.49%、release CRC 1.72%、producer 4.18% |
| `Runtime.begin` | 9.79% | producer |
| `Journal.reserve` | 8.87% | producer |
| `encodeJsonWithAttributes` | 8.77% | consumer render |
| `Runtime.releaseAdmissionView` | 4.87% | producer |
| `decimal.writeNative` | 4.50% | consumer render |
| `Runtime.end` | 4.33% | producer |
| `codec.encodeSized` | 3.46% | producer |
| `memcpyFast` | 3.33% | consumer render 1.16%，其余producer |
| `decimal.writeLargeNative` | 2.30% | consumer render |
| `Runtime.drainJournal` | 2.14% | consumer |
| `Runtime.releaseWrittenRun` | 1.67% | consumer |

consumer侧的主要成本是JSON render（`encodeJsonWithAttributes`+decimal约15.6%总cycles）、两次slot CRC（约6.2%）和memcpy；producer侧仍是begin/reserve/encode/CRC/commit。批量确认已经减少了per-record reclaim atomics，但没有改变render与write仍在唯一consumer线程串行的事实。

## 用途与边界

该profile只用于定位下一候选，不是速度排名，也不代表可达优化百分比。它支持优先验证“consumer render与写出重叠/并行”，而不是继续减少CRC指令或producer admission。原始perf数据见[perf.data.xz](perf.data.xz)，完整报告见[report.txt](report.txt)。
