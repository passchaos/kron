# JSON member最终源码：E-core完整前端对照

当前源码保留JSON属性前缀直接写入和cold fallback、不可变predicate route掩码；JSON整数候选全部撤回，默认CRC及恢复协议保持。精确源码、二进制、Foundation原始来源/依赖和环境在manifest.json；优化前后、所有负向与完整门禁见[实验报告](../../../evidence/2026-11-02-json-member-direct/README.md)。

真实Foundation/logging + spdlog及+tracing与kron managed async/SPSC，Memory/Mmap、P1/P4、batch/sampled、五轮；CPU16/18/20/22/24/26，100000事件+1000warmup，系统时钟、五typed数值字段、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。160项全部逐条核对16,160,000条JSON，pending/drop=0，无设备durable请求。

关闭吞吐对tracing的16对中，peer领先12、不确定4；对spdlog，peer领先10、kron领先2、不确定4。目标为target_not_met_in_selected_cases，未全面超过两个组合。至少5轮、两侧和配对spread≤10%、95%区间不跨1才判断本轮局部领先；init/lifecycle/p99/p99.9独立报告，慢值保留。

results.jsonl、analysis.json、comparison.md保留全部配置、原始报告和资格。此窗口不外推[P-core](../2026-11-02-json-member-pcore/README.md)、不同CPU或非Linux设备。

```sh
python3 bench/cpp_reference/run.py --output-dir FRESH \
  --libraries foundation,foundation_tracing,kron --kron-frontend managed \
  --kron-modes async,spsc --kron-storages memory,mmap --events 100000 --warmup 1000 \
  --repeats 5 --producers 1,4 --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py FRESH
```
