# Direct shared peak当前Foundation E-core对照

完成160项，逐条核对16,160,000条物理JSON。当前source hash在matrix后确认不变，driver对两个Foundation真实前端与managed kron同轮测量。

CPU16/18/20/22/24/26，Memory/Mmap、async/SPSC、P1/P4、batch/sampled、100k事件+1000warmup、5轮；五typed值/fullmetadata/system clock、256槽/512B、64KiB portable文件，written flush→shutdown→cleanup。默认CRC、全部检查及实时written保持，未请求device durable。

| 前端 | kron局部领先 | peer局部领先 | 不确定 |
| --- | ---: | ---: | ---: |
| Foundation + spdlog | 3 | 5 | 8 |
| Foundation + tracing | 0 | 11 | 5 |

written-close目标为`target_not_met_in_selected_cases`。对tracing多数场景仍有局部稳定差距；对spdlog只有三个selectedMemoryP1场景领先。不能把峰值稳态跳过CAS或PMU局部周期改善直接叠加到跨库ratio。初始化/lifecycle/调用p99/p99.9各自资格独立，噪声或区间重叠保持inconclusive。

所有ratio、输入差异、依赖/toolchain/source/binary身份在manifest、results、analysis、kron-source-provenance；comparison.md用于阶段/尾部，analysis.json是配对资格；summary.json仅driver分组统计。真实SIGKILL恢复与平台范围见主实验，不能扩展到物理断电或非Linux设备。
