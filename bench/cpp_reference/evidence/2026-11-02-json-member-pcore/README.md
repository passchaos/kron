# JSON member最终源码：P-core完整前端对照

与[E-core](../2026-11-02-json-member-ecore/README.md)相同源码，真实Foundation/logging + spdlog、+tracing与kron public managed async/SPSC。CPU0/2/4/6/8/10，Memory/Mmap、P1/P4、batch/sampled、五轮，100000事件+1000warmup、系统时钟、五typed数值字段、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。160项核对16,160,000条完整JSON，pending/drop=0，没有请求设备durable。

关闭吞吐对tracing16对中kron局部领先2、不确定14，对spdlog局部领先1、不确定15。多数配对受波动或区间跨1影响，整体inconclusive，不宣告全面超过两个前端。每组init、lifecycle与p99/p99.9独立判定，所有慢值继续保留。

精确来源与hash、原始结果和资格分别在manifest.json、results.jsonl、analysis.json、comparison.md。完整优化/否决/百万条复测与应用oracle见[实验报告](../../../evidence/2026-11-02-json-member-direct/README.md)。复现E-core命令将affinity换为0,2,4,6,8,10；不同源码或窗口生成自己的资格。
