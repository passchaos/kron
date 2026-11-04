# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[0, 2, 4, 7, 9, 12]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | — | 2.214 | — | 2.090 | 无 |
| foundation mmap | — | 2.437 | — | 2.434 | 有 |
| foundation_tracing memory | — | 2.164 | — | 2.076 | 无 |
| foundation_tracing mmap | — | 2.274 | — | 2.272 | 有 |
| kron async-memory-inline | — | 2.523 | — | 2.510 | 无 |
| kron async-mmap-inline | — | 2.284 | — | 2.278 | 有 |
| kron spsc-memory-inline | — | 2.908 | — | 2.889 | 无 |
| kron spsc-mmap-inline | — | 3.227 | — | 3.194 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | — | 652 / 32,560 | — | 0.247 |
| foundation mmap | — | 733 / 14,998 | — | 21.745 |
| foundation_tracing memory | — | 685 / 36,056 | — | 0.181 |
| foundation_tracing mmap | — | 695 / 14,458 | — | 20.722 |
| kron async-memory-inline | — | 1,052 / 1,748 | — | 0.741 |
| kron async-mmap-inline | — | 974 / 1,584 | — | 7.780 |
| kron spsc-memory-inline | — | 727 / 1,209 | — | 0.890 |
| kron spsc-mmap-inline | — | 798 / 1,198 | — | 1025.381 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | — | 48.819 | — | 0.051 | 299.33 |
| foundation mmap | — | 63.559 | — | 0.057 | 299.33 |
| foundation_tracing memory | — | 49.048 | — | 0.001 | 299.33 |
| foundation_tracing mmap | — | 68.625 | — | 0.009 | 299.33 |
| kron async-memory-inline | — | 41.519 | — | 0.034 | 299.37 |
| kron async-mmap-inline | — | 53.375 | — | 0.027 | 299.37 |
| kron spsc-memory-inline | — | 37.199 | — | 0.034 | 299.03 |
| kron spsc-mmap-inline | — | 1056.773 | — | 0.030 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 4 | batch | 1.201 | 0.937..10.271 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.160 | 0.905..7.197 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.210 | 1.152..1.251 | kron_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.250 | 1.220..1.341 | kron_leads |
| async-mmap-inline | foundation | 4 | batch | 0.971 | 0.910..1.166 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.069 | 0.928..1.242 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.059 | 0.627..1.159 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 1.052 | 0.539..1.360 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.306 | 1.165..13.290 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.346 | 1.218..9.313 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.203 | 1.034..1.662 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.196 | 1.122..1.805 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.309 | 0.964..1.469 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.419 | 0.921..1.549 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.357 | 1.043..1.647 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.348 | 1.025..1.624 | inconclusive |
