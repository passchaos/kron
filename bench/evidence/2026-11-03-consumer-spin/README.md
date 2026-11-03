# Consumer spin idle候选

P4/mmap PMU显示kron用户态指令/周期少于Foundation但wall-clock更慢，且Foundation producer_format与kron consumer deferred format不同。先验证一个最小假设：把benchmark reference的consumer idle从`.sleep`改为`.spin`，看减少wake延迟是否能缩小P4差距。library源码、输出格式、CRC、队列预算和关闭协议不变；只改`bench/cpp_reference/kron_reference.zig`的idle选择。

## E-core A/B

同一library源码构建before（`.sleep`，生产binary `68c0...`）与after（`.spin`，`bf37...`），E-core async、memory/mmap、P1/P4、batch/sampled、inline/schema：160 trials，逐条核验16,160,000条完整JSON。

- 0 qualified lead。
- 6 qualified negative：
  - `async-memory P4 batch schema` written 0.9803、written+flush 0.9803、lifecycle 0.9806。
  - `async-mmap P1 sampled schema` written 0.9708、written+flush 0.9708、p50 0.9251。
- 其余98轴inconclusive。

spin consumer持续占用一个核，却没有降低P4 producer/consumer流水线差距，反而在memory P4 batch和mmap P1 sampled出现稳定负向。该结果否定了“P4差距主要是sleep/wake延迟”的假设；生产继续使用`.sleep`，benchmark reference不变。

证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`；before/after binary与修改后的reference在`.zig-cache/consumer-spin`（未进入生产）。整体“业界最佳”目标仍未完成。
