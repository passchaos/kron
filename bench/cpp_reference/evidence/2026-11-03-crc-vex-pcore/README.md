# CRC VEX当前Foundation P-core对照

完成160项，逐条核对16,160,000条物理JSON。两个Foundation真实前端与当前managed kron同轮比较；CPU0/2/4/6/8/10。source hash在matrix后核对不变。

输入/预算/系统时钟/written flush→shutdown→cleanup与[E-core报告](../2026-11-03-crc-vex-ecore/README.md)相同，100k事件+1000warmup、5次轮换、P1/P4、async/SPSC、Memory/Mmap、batch/sampled、full JSON，未请求device durable。

| 前端 | kron局部领先 | peer局部领先 | 不确定 |
| --- | ---: | ---: | ---: |
| Foundation + spdlog | 5 | 0 | 11 |
| Foundation + tracing | 5 | 1 | 10 |

written-close目标仍为`target_not_met_in_selected_cases`：SPSC Memory P1 batch对tracing约0.928×并达到本轮局部负向资格。P4部分组领先，不代表所有线程数/生命周期/尾部都超过。宿主波动超10%或区间跨1的组保持inconclusive，不能按正向中位直接排名。

全部source/依赖/toolchain/binary与原始结果在manifest、results、analysis与kron-source-provenance中；`comparison.md`报告阶段/尾部，`analysis.json`提供paired qualification，driver的`summary.json`只保存分组统计。完整Foundation源已无损归档并核对tree hash。
