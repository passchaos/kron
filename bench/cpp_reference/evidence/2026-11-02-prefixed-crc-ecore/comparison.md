# 完整日志流程实测

共 160 个试验，逐条核对 16,160,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。

下表均为5次试验的中位数。吞吐单位为百万条/秒，包含producer、后台格式化/文件写出和最终written flush；关闭列进一步包含shutdown和对象清理。它们都没有请求设备durable。

| 配置 | 1线程 written+flush | 4线程 written+flush | 1线程包含关闭 | 4线程包含关闭 | 进程崩溃恢复 |
| --- | ---: | ---: | ---: | ---: | --- |
| foundation memory | 1.791 | 2.348 | 1.789 | 2.345 | 无 |
| foundation mmap | 2.202 | 2.764 | 2.195 | 2.758 | 有 |
| foundation_tracing memory | 2.137 | 2.203 | 2.132 | 2.200 | 无 |
| foundation_tracing mmap | 2.756 | 3.183 | 2.751 | 3.177 | 有 |
| kron async-memory-inline | 1.836 | 1.698 | 1.832 | 1.695 | 无 |
| kron async-mmap-inline | 1.827 | 1.703 | 1.817 | 1.700 | 有 |
| kron spsc-memory-inline | 1.865 | 1.947 | 1.860 | 1.941 | 无 |
| kron spsc-mmap-inline | 1.852 | 1.933 | 1.848 | 1.927 | 有 |

| 配置 | 1线程调用 p50/p99 ns | 4线程调用 p50/p99 ns | 1线程初始化 ms | 4线程初始化 ms |
| --- | ---: | ---: | ---: | ---: |
| foundation memory | 379 / 776 | 669 / 46,434 | 0.265 | 0.265 |
| foundation mmap | 434 / 874 | 750 / 8,537 | 19.602 | 19.581 |
| foundation_tracing memory | 295 / 634 | 720 / 46,387 | 0.245 | 0.254 |
| foundation_tracing mmap | 344 / 780 | 749 / 7,965 | 19.368 | 19.489 |
| kron async-memory-inline | 310 / 581 | 838 / 46,024 | 0.722 | 0.704 |
| kron async-mmap-inline | 306 / 567 | 850 / 45,988 | 14.122 | 11.350 |
| kron spsc-memory-inline | 298 / 513 | 289 / 461 | 0.835 | 1.061 |
| kron spsc-mmap-inline | 295 / 500 | 284 / 479 | 20.259 | 31.336 |

| 配置 | 1线程100k完整生命周期 ms | 4线程100k完整生命周期 ms | 1线程shutdown ms | 4线程shutdown ms | 4线程输出 bytes/event |
| --- | ---: | ---: | ---: | ---: | ---: |
| foundation memory | 56.972 | 43.966 | 0.065 | 0.058 | 299.33 |
| foundation mmap | 65.909 | 55.191 | 0.077 | 0.070 | 299.33 |
| foundation_tracing memory | 47.950 | 46.453 | 0.015 | 0.010 | 299.33 |
| foundation_tracing mmap | 55.099 | 48.735 | 0.010 | 0.012 | 299.33 |
| kron async-memory-inline | 56.363 | 60.644 | 0.038 | 0.035 | 299.37 |
| kron async-mmap-inline | 70.068 | 71.437 | 0.036 | 0.101 | 299.37 |
| kron spsc-memory-inline | 55.552 | 53.520 | 0.031 | 0.029 | 299.03 |
| kron spsc-mmap-inline | 74.036 | 84.208 | 0.036 | 0.026 | 299.03 |

各指标的min/max、relative spread和10%噪声门限结论在analysis.json中；不要用这张中位数表替代稳定性资格。输出文件逐条核验后可被驱动清理，原始试验报告保留文件哈希和物理字节/记录数。

Foundation 配对资格：`target_not_met_in_selected_cases`。比值大于1表示kron更快；至少5轮、两侧和配对比值spread均≤10%、95%配对bootstrap区间不跨1才判断领先。初始化、完整生命周期与p99/p99.9单独判定。

| kron配置 | Foundation前端 | producers | phase | 包含关闭速度比 | 95%区间 | 资格 |
| --- | --- | ---: | --- | ---: | --- | --- |
| async-memory-inline | foundation | 1 | batch | 1.020 | 1.012..1.052 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | batch | 0.861 | 0.832..0.895 | peer_leads |
| async-memory-inline | foundation | 1 | sampled | 1.081 | 1.043..1.140 | kron_leads |
| async-memory-inline | foundation_tracing | 1 | sampled | 0.935 | 0.900..0.943 | peer_leads |
| async-memory-inline | foundation | 4 | batch | 0.737 | 0.722..0.740 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | batch | 0.770 | 0.752..0.788 | peer_leads |
| async-memory-inline | foundation | 4 | sampled | 0.775 | 0.745..0.803 | peer_leads |
| async-memory-inline | foundation_tracing | 4 | sampled | 0.792 | 0.771..0.826 | peer_leads |
| async-mmap-inline | foundation | 1 | batch | 0.829 | 0.809..0.871 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | batch | 0.663 | 0.632..0.671 | peer_leads |
| async-mmap-inline | foundation | 1 | sampled | 0.924 | 0.893..0.944 | peer_leads |
| async-mmap-inline | foundation_tracing | 1 | sampled | 0.752 | 0.745..0.769 | peer_leads |
| async-mmap-inline | foundation | 4 | batch | 0.615 | 0.601..0.675 | inconclusive |
| async-mmap-inline | foundation_tracing | 4 | batch | 0.518 | 0.482..0.550 | inconclusive |
| async-mmap-inline | foundation | 4 | sampled | 0.605 | 0.594..0.634 | peer_leads |
| async-mmap-inline | foundation_tracing | 4 | sampled | 0.554 | 0.512..0.580 | inconclusive |
| spsc-memory-inline | foundation | 1 | batch | 1.047 | 1.020..1.084 | kron_leads |
| spsc-memory-inline | foundation_tracing | 1 | batch | 0.862 | 0.856..0.892 | peer_leads |
| spsc-memory-inline | foundation | 1 | sampled | 1.110 | 1.051..1.172 | inconclusive |
| spsc-memory-inline | foundation_tracing | 1 | sampled | 0.944 | 0.930..0.963 | peer_leads |
| spsc-memory-inline | foundation | 4 | batch | 0.833 | 0.811..0.847 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | batch | 0.884 | 0.845..0.896 | peer_leads |
| spsc-memory-inline | foundation | 4 | sampled | 0.879 | 0.833..0.890 | peer_leads |
| spsc-memory-inline | foundation_tracing | 4 | sampled | 0.900 | 0.876..0.916 | peer_leads |
| spsc-mmap-inline | foundation | 1 | batch | 0.829 | 0.823..0.909 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 1 | batch | 0.669 | 0.648..0.693 | peer_leads |
| spsc-mmap-inline | foundation | 1 | sampled | 0.946 | 0.934..0.969 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 1 | sampled | 0.762 | 0.758..0.817 | peer_leads |
| spsc-mmap-inline | foundation | 4 | batch | 0.712 | 0.665..0.772 | inconclusive |
| spsc-mmap-inline | foundation_tracing | 4 | batch | 0.604 | 0.558..0.609 | inconclusive |
| spsc-mmap-inline | foundation | 4 | sampled | 0.684 | 0.674..0.718 | peer_leads |
| spsc-mmap-inline | foundation_tracing | 4 | sampled | 0.633 | 0.581..0.659 | inconclusive |
