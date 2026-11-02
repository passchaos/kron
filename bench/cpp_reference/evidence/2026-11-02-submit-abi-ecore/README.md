# Runtime内部提交借用：E-core完整前端对照

最终源码只改变本次调用内的Context/Ref/Event传递，公共快照、CRC和恢复协议保持。真实Foundation/logging + spdlog、+tracing与kron managed async/SPSC，CPU16/18/20/22/24/26，Memory/Mmap、P1/P4、batch/sampled、五轮。100000事件+1000warmup、系统墙钟、五typed数字、full JSON、256槽/512B、64KiB portable文件，written flush→shutdown→cleanup。160项逐条核对16,160,000条JSON，pending/drop=0，没有请求device durable。

关闭吞吐配对对spdlog16对中peer领先3、不确定13；对tracing16对全部不确定。未证明同时超过两个组合；target_not_met_in_selected_cases只反映选定关闭吞吐目标，初始化、生命周期和尾部仍分别检查。两侧/配对spread≤10%、至少5轮、95%区间不跨1才给局部资格；不将窗口波动或未确认差距称为优化后排名。

manifest.json保留逐生产文件hash、二进制、Foundation原始来源/依赖和环境；results.jsonl、analysis.json、comparison.md保留所有慢值、完成阶段和配对资格。当前改动与候选/栈/正确性范围见[Runtime提交实验](../../../evidence/2026-11-02-submit-abi/README.md)。此窗口不代替[P-core](../2026-11-02-submit-abi-pcore/README.md)、应用或非Linux设备证据。

```sh
python3 bench/cpp_reference/run.py --output-dir FRESH \
  --libraries foundation,foundation_tracing,kron --kron-frontend managed \
  --kron-modes async,spsc --kron-storages memory,mmap --events 100000 --warmup 1000 \
  --repeats 5 --producers 1,4 --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py FRESH
```
