# Direct shared peak当前Foundation P-core对照

完成160项，逐条核对16,160,000条物理JSON，kron source hash在matrix后确认不变。两个Foundation真实前端与managed日志入口同轮比较。

CPU0/2/4/6/8/10。输入/预算/协议/完成边界与[E-core](../2026-11-03-peak-direct-ecore/README.md)相同；100k事件+1000warmup、5轮、Memory/Mmap、async/SPSC、P1/P4、batch/sampled、full JSON/system clock、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。default CRC及所有检查保持，无device durable。

| 前端 | kron局部领先 | peer局部领先 | 不确定 |
| --- | ---: | ---: | ---: |
| Foundation + spdlog | 7 | 0 | 9 |
| Foundation + tracing | 4 | 0 | 12 |

written-close整体为`inconclusive`；P4有局部领先，P1与其他组仍受两输入/ratio spread或置信区间限制。没有证明同时超过两个组合、全部线程数/初始化/生命周期/尾部；正向中位不是完成证据。E-core仍有明确peer领先，整体目标未达到。

配对资格见analysis.json，阶段/尾部见comparison.md，driver summary仅分组统计；全部依赖、source/toolchain/binary/physicalrecords在manifest/results/source-provenance，Foundation owning源已无损归档并核对tree。
