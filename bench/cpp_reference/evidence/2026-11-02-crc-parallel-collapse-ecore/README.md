# 当前CRC并行合并：E-core同轮完整前端对照

同轮真实Foundation/logging + spdlog、Foundation/logging + tracing与kron public managed async/SPSC，默认CRC保持。源码逐文件hash、二进制、Foundation冻结源码与依赖、CPU/文件系统在`manifest.json`。候选只并行合并CRC四个lane，完整门禁和所有before/after见[CRC报告](../../../evidence/2026-11-02-crc-parallel-collapse/README.md)。

CPU16/18/20/22/24/26，Memory/Mmap、P1/P4、batch/sampled、五次重复，100000事件+1000warmup、系统时钟、五typed数值字段、full JSON、256槽/512B、64KiB portable文件，written flush→shutdown→cleanup。160项逐条核对16,160,000条JSON，drop/pending=0，不请求设备durable。

关闭吞吐配对对spdlog的16对中kron局部领先2、spdlog领先5、inconclusive 9；对tracing，tracing领先14、inconclusive 2。至少5轮、两侧与配对比值spread≤10%、95%bootstrap区间不跨1才判局部领先。目标为`target_not_met_in_selected_cases`；初始化、完整生命周期和p99/p99.9独立列出，不能用个别组代替完整性能验收。

所有快慢值、命令、输出哈希与计数在`results.jsonl`、`analysis.json`、`comparison.md`；源绑定本轮，不外推[P-core](../2026-11-02-crc-parallel-collapse-pcore/README.md)或未验证平台。仍未全面超过两个Foundation前端。

```sh
python3 bench/cpp_reference/run.py --output-dir FRESH \
  --libraries foundation,foundation_tracing,kron --kron-frontend managed \
  --kron-modes async,spsc --kron-storages memory,mmap --events 100000 --warmup 1000 \
  --repeats 5 --producers 1,4 --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py FRESH
```
