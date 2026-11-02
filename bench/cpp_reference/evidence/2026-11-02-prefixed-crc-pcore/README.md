# P-core CRC候选完整前端对照

**此候选已撤回；本页不代表当前生产源码的新排名。** 精确源码、二进制、Foundation原始源码/依赖、CPU/文件系统与负载身份在`manifest.json`。与[E-core窗口](../2026-11-02-prefixed-crc-ecore/README.md)相同生产源码，保留默认三个CRC校验和v1/v2协议。

CPU0/2/4/6/8/10，两个真实Foundation前端与kron public managed async/SPSC，Memory/Mmap、P1/P4、batch/sampled，五次重复；100000事件+1000warmup、系统时钟、五typed数值字段、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。160项全部通过物理JSON核对，共16,160,000条；drop/pending均为0。未请求设备durable。

关闭吞吐配对资格：对spdlog 16对中，kron局部领先1、inconclusive 15；对tracing 16对中，kron局部领先1、tracing局部领先1、inconclusive 14。宿主波动使多数配对未通过10%门限或区间跨1，不能据中位数认定全面胜者。完整阶段、尾延迟和所有慢值在`results.jsonl`、`analysis.json`、`comparison.md`。目标为`target_not_met_in_selected_cases`。

候选CRC其他长度仍有负向成本，全部撤回，见[完整实验](../../../evidence/2026-11-02-prefixed-crc/README.md)。使用E-core命令将affinity换为`0,2,4,6,8,10`可复现P-core范围；重新运行当前源码会生成自己的身份，不能继承本页资格。
