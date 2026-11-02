# 当前CRC并行合并：P-core同轮完整前端对照

与[E-core](../2026-11-02-crc-parallel-collapse-ecore/README.md)相同生产源码，两个真实Foundation前端与kron public managed async/SPSC，默认CRC。CPU0/2/4/6/8/10，Memory/Mmap、P1/P4、batch/sampled、五次重复；100000事件+1000warmup、系统时钟、五typed数值字段、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。160项全部逐条核对16,160,000条JSON，drop/pending=0，未请求设备durable。

关闭吞吐配对对spdlog的16对中kron局部领先3、inconclusive 13；对tracing kron局部领先6、inconclusive 10，没有确认peer领先组。多数配对受波动/区间影响，整体`inconclusive`，不能认定全面超过两个前端。各指标阶段与p99/p99.9独立报告，不借其他组替代。

源码逐文件hash、二进制、Foundation冻结来源/依赖、环境与原始快慢值在`manifest.json`、`results.jsonl`、`analysis.json`、`comparison.md`。本轮优化、负向复测、完整门禁见[CRC报告](../../../evidence/2026-11-02-crc-parallel-collapse/README.md)。复现E-core命令将affinity改为`0,2,4,6,8,10`，不同源码/窗口生成自己的资格。
