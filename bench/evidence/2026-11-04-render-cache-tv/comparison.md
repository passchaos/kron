# 完整日志流程实测

共 80 个试验，逐条核对 8,080,000 条完整日志。固定 CPU affinity：[21, 23, 25, 27, 29, 31]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | — | 2.284 | — | 2.281 | 无 |
| foundation mmap | — | 2.856 | — | 2.850 | 有 |
| foundation_tracing memory | — | 2.142 | — | 2.126 | 无 |
| foundation_tracing mmap | — | 2.609 | — | 2.604 | 有 |
| kron async-memory-inline | — | 2.952 | — | 2.928 | 无 |
| kron async-mmap-inline | — | 2.955 | — | 2.941 | 有 |
| kron spsc-memory-inline | — | 3.463 | — | 3.436 | 无 |
| kron spsc-mmap-inline | — | 3.430 | — | 3.399 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | — | 607 / 45,824 | — | 0.255 |
| foundation mmap | — | 900 / 8,554 | — | 19.276 |
| foundation_tracing memory | — | 697 / 46,950 | — | 0.230 |
| foundation_tracing mmap | — | 766 / 7,940 | — | 207.564 |
| kron async-memory-inline | — | 1,035 / 8,361 | — | 0.763 |
| kron async-mmap-inline | — | 1,024 / 8,075 | — | 15.585 |
| kron spsc-memory-inline | — | 599 / 849 | — | 1.106 |
| kron spsc-mmap-inline | — | 596 / 860 | — | 55.465 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | — | 44.869 | — | 0.058 | 299.33 |
| foundation mmap | — | 55.168 | — | 0.068 | 299.33 |
| foundation_tracing memory | — | 48.021 | — | 0.010 | 299.33 |
| foundation_tracing mmap | — | 241.769 | — | 0.011 | 299.33 |
| kron async-memory-inline | — | 35.933 | — | 0.035 | 299.37 |
| kron async-mmap-inline | — | 50.905 | — | 0.033 | 299.37 |
| kron spsc-memory-inline | — | 31.036 | — | 0.058 | 299.03 |
| kron spsc-mmap-inline | — | 85.657 | — | 0.043 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 4 | batch | 1.272 | 1.086..1.371 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 1.390 | 1.200..13.768 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 1.298 | 1.176..1.334 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | sampled | 1.368 | 1.271..1.395 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 1.032 | 0.974..1.149 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 1.134 | 0.956..1.160 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 1.152 | 1.051..1.226 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.923 | 0.882..0.959 | peer_leads |
| spsc-memory-inline | foundation | 4 | batch | 1.538 | 1.363..1.655 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | batch | 1.647 | 1.575..15.082 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 1.507 | 1.344..1.564 | inconclusive |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 1.546 | 1.473..1.681 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 1.130 | 1.011..1.321 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 1.139 | 1.073..1.389 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 1.391 | 1.166..1.488 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 1.105 | 0.992..1.119 | inconclusive |
