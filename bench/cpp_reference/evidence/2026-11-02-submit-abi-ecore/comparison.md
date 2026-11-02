# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.716 | 2.090 | 1.713 | 2.087 | 无 |
| foundation mmap | 1.962 | 2.461 | 1.954 | 2.457 | 有 |
| foundation_tracing memory | 2.055 | 2.079 | 2.051 | 2.077 | 无 |
| foundation_tracing mmap | 2.572 | 2.619 | 2.563 | 2.612 | 有 |
| kron async-memory-inline | 1.864 | 1.715 | 1.853 | 1.709 | 无 |
| kron async-mmap-inline | 1.705 | 1.609 | 1.692 | 1.604 | 有 |
| kron spsc-memory-inline | 1.900 | 1.978 | 1.896 | 1.972 | 无 |
| kron spsc-mmap-inline | 1.769 | 1.831 | 1.765 | 1.825 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 393 / 886 | 727 / 50,240 | 0.261 | 0.262 |
| foundation mmap | 436 / 1,237 | 774 / 8,762 | 12.691 | 20.040 |
| foundation_tracing memory | 290 / 700 | 752 / 47,815 | 0.224 | 0.241 |
| foundation_tracing mmap | 342 / 1,007 | 814 / 7,826 | 12.781 | 12.484 |
| kron async-memory-inline | 326 / 554 | 831 / 44,970 | 0.719 | 0.708 |
| kron async-mmap-inline | 333 / 800 | 868 / 45,986 | 11.439 | 14.140 |
| kron spsc-memory-inline | 294 / 498 | 279 / 431 | 0.808 | 1.063 |
| kron spsc-mmap-inline | 290 / 790 | 277 / 999 | 20.146 | 36.936 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 59.854 | 49.173 | 0.083 | 0.058 | 299.33 |
| foundation mmap | 66.192 | 59.788 | 0.114 | 0.063 | 299.33 |
| foundation_tracing memory | 50.044 | 49.360 | 0.016 | 0.009 | 299.33 |
| foundation_tracing mmap | 52.618 | 52.984 | 0.016 | 0.009 | 299.33 |
| kron async-memory-inline | 55.771 | 60.333 | 0.097 | 0.093 | 299.37 |
| kron async-mmap-inline | 73.149 | 76.362 | 0.071 | 0.031 | 299.37 |
| kron spsc-memory-inline | 54.381 | 52.659 | 0.035 | 0.029 | 299.03 |
| kron spsc-mmap-inline | 77.344 | 88.486 | 0.032 | 0.029 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.082 | 1.017..1.302 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | batch | 0.910 | 0.827..1.070 | inconclusive |
| async-memory-inline | foundation | 1 | sampled | 1.301 | 1.088..1.510 | inconclusive |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.999 | 0.909..1.144 | inconclusive |
| async-memory-inline | foundation | 4 | batch | 0.815 | 0.797..0.887 | inconclusive |
| async-memory-inline | foundation_tracing | 4 | batch | 0.850 | 0.731..0.865 | inconclusive |
| async-memory-inline | foundation | 4 | sampled | 0.850 | 0.837..0.859 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.861 | 0.750..0.876 | inconclusive |
| async-mmap-inline | foundation | 1 | batch | 0.863 | 0.787..0.909 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.665 | 0.637..0.684 | inconclusive |
| async-mmap-inline | foundation | 1 | sampled | 0.935 | 0.912..1.097 | inconclusive |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.778 | 0.734..0.831 | inconclusive |
| async-mmap-inline | foundation | 4 | batch | 0.653 | 0.619..0.718 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.620 | 0.545..0.670 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.618 | 0.561..0.655 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.567 | 0.476..0.576 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.151 | 1.026..1.332 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.931 | 0.834..1.109 | inconclusive |
| spsc-memory-inline | foundation | 1 | sampled | 1.349 | 1.107..1.559 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 1.024 | 0.939..1.166 | inconclusive |
| spsc-memory-inline | foundation | 4 | batch | 0.945 | 0.918..0.977 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.952 | 0.856..0.970 | inconclusive |
| spsc-memory-inline | foundation | 4 | sampled | 0.958 | 0.945..0.985 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.969 | 0.869..0.986 | inconclusive |
| spsc-mmap-inline | foundation | 1 | batch | 0.913 | 0.809..0.923 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.689 | 0.629..0.739 | inconclusive |
| spsc-mmap-inline | foundation | 1 | sampled | 0.983 | 0.965..1.086 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.818 | 0.786..0.865 | inconclusive |
| spsc-mmap-inline | foundation | 4 | batch | 0.739 | 0.689..0.799 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.693 | 0.633..0.758 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.704 | 0.638..0.767 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.622 | 0.542..0.675 | inconclusive |
