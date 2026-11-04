# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[17, 20, 25, 27, 29, 31]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | — | 2.113 | — | 2.110 | 无 |
| foundation mmap | — | 3.097 | — | 3.089 | 有 |
| foundation_tracing memory | — | 2.136 | — | 2.134 | 无 |
| foundation_tracing mmap | — | 2.630 | — | 2.625 | 有 |
| kron async-memory-inline | — | 2.737 | — | 2.724 | 无 |
| kron async-mmap-inline | — | 2.922 | — | 2.906 | 有 |
| kron spsc-memory-inline | — | 3.375 | — | 3.349 | 无 |
| kron spsc-mmap-inline | — | 3.318 | — | 3.290 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | — | 638 / 47,305 | — | 0.259 |
| foundation mmap | — | 769 / 8,861 | — | 19.938 |
| foundation_tracing memory | — | 721 / 47,692 | — | 0.244 |
| foundation_tracing mmap | — | 799 / 9,671 | — | 21.250 |
| kron async-memory-inline | — | 922 / 1,457 | — | 0.768 |
| kron async-mmap-inline | — | 1,023 / 8,872 | — | 11.886 |
| kron spsc-memory-inline | — | 613 / 873 | — | 1.113 |
| kron spsc-mmap-inline | — | 596 / 886 | — | 46.110 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | — | 48.536 | — | 0.059 | 299.33 |
| foundation mmap | — | 52.093 | — | 0.082 | 299.33 |
| foundation_tracing memory | — | 47.834 | — | 0.010 | 299.33 |
| foundation_tracing mmap | — | 62.518 | — | 0.013 | 299.33 |
| kron async-memory-inline | — | 38.307 | — | 0.041 | 299.37 |
| kron async-mmap-inline | — | 48.437 | — | 0.036 | 299.37 |
| kron spsc-memory-inline | — | 31.785 | — | 0.037 | 299.03 |
| kron spsc-mmap-inline | — | 78.528 | — | 0.042 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 4 | batch | 1.291 | 1.130..1.357 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.270 | 1.163..1.373 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.279 | 0.908..2.646 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.152 | 0.901..1.365 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 0.960 | 0.913..1.011 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.100 | 0.871..1.228 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.025 | 0.874..1.128 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.997 | 0.809..1.145 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 1.581 | 1.327..1.649 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.570 | 1.357..1.617 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.605 | 1.455..3.290 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.545 | 1.433..1.684 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.069 | 0.928..1.238 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.173 | 1.067..1.333 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.211 | 1.157..1.369 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.204 | 1.079..1.375 | inconclusive |
