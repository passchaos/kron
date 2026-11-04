# 完整日志流程实测

共 30 个试验，逐条核对 3,030,000 条完整日志。固定 CPU affinity：[1, 3, 5, 7, 9, 11]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation mmap | 2.083 | — | 2.078 | — | 有 |
| foundation_tracing mmap | 2.646 | — | 2.641 | — | 有 |
| kron spool-mmap-inline | 3.613 | — | 3.320 | — | 无 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation mmap | 458 / 907 | — | 18.021 | — |
| foundation_tracing mmap | 323 / 819 | — | 16.502 | — |
| kron spool-mmap-inline | 209 / 1,286 | — | 15.686 | — |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation mmap | 66.428 | — | 0.088 | — | — |
| foundation_tracing mmap | 54.895 | — | 0.014 | — | — |
| kron spool-mmap-inline | 46.993 | — | 1.576 | — | — |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`inconclusive`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| spool-mmap-inline | foundation | 1 | batch | 1.613 | 1.514..1.636 | kron_leads |
| spool-mmap-inline | foundation_tracing | 1 | batch | 1.287 | 1.204..1.427 | inconclusive |
| spool-mmap-inline | foundation | 1 | sampled | 1.563 | 1.527..1.604 | kron_leads |
| spool-mmap-inline | foundation_tracing | 1 | sampled | 1.242 | 1.098..1.289 | inconclusive |
