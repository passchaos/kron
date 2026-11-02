# Runtime内部提交借用：P-core完整前端对照

与[E-core](../2026-11-02-submit-abi-ecore/README.md)相同最终生产源码，两个真实Foundation前端与kron managed async/SPSC。CPU0/2/4/6/8/10，Memory/Mmap、P1/P4、batch/sampled、五轮；100000事件+1000warmup、系统墙钟、五typed数字、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。160项核对16,160,000条完整JSON，pending/drop=0，无device durable请求。

关闭吞吐配对对spdlog16对中kron局部领先4、其余12不确定；对tracing局部领先2、其余14不确定。整体inconclusive，没有全面超过两个前端。初始化、完整生命周期与调用p99/p99.9独立报告，所有负向/慢值保留。不能把局部组的资格或历史不同源码百分比外推到完整库性能。

manifest.json、results.jsonl、analysis.json、comparison.md保存source/binary、来源/依赖、完整物理记录hash和每组统计。机制、public快照回归和完整门禁见[Runtime提交报告](../../../evidence/2026-11-02-submit-abi/README.md)。E-core复现命令改affinity为0,2,4,6,8,10即可选择本拓扑；新源码/窗口生成自己的资格。
