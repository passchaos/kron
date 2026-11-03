# 当前生产源码的完整E/P Foundation矩阵

保留V3 schema journal CRC后，用当前`src/root.zig`完成双拓扑完整同边界跨库对照。每个拓扑240 trials，逐条核验24,240,000条完整JSON；配置为managed async/SPSC、Memory/Mmap、P1/P4、batch/sampled、inline/schema、Foundation+spdlog、Foundation+Rust tracing、kron，100k events/1k warmup/5 repeats。

## 结果

- **E-core**：`target_not_met_in_selected_cases`。轴计数29 kron lead、94 peer lead、293 inconclusive。
- **P-core**：`inconclusive`。2 kron lead（均为`spsc-mmap-schema P4 batch` vs tracing，written 1.1214、written+flush 1.1231）、414 inconclusive、0 peer lead。
- E-core的kron qualified lead集中在P1 memory batch：`async-memory-schema P1 batch` vs foundation 1.015/1.016、`spsc-memory-inline P1 batch` 1.058/1.059、`spsc-memory-schema P1 batch` 1.036/1.038；另有部分sampled p50/p99/p999局部领先。
- Foundation前端在P4和mmap组领先明显：`async-mmap-inline P4 batch` vs foundation 0.538、`async-mmap-schema P4 batch` 0.552、`spsc-mmap-inline P4 batch` 0.611、`spsc-mmap-schema P4 batch` 0.615；tracing在P1 sampled也多数领先（约0.74–0.92）。

这说明V3保留改善了kron schema P1 batch并取得对Foundation的qualified lead，但kron仍未在完整矩阵同时超过两个前端；P4、mmap和tracing路径仍是主要差距。结果绑定当前宿主窗口、spread/区间和5 repeats，不构成普适排名；P-core窗口受宿主负载影响，仅`spsc-mmap-schema P4 batch` vs tracing有qualified lead。

原始`results.jsonl`、`manifest.json`、`analysis.json`、`comparison.md`和三个参考binary身份分别保留在 [E-core](.) 与 [P-core](../2026-11-03-current-foundation-full-pcore/)。完整文档入口见[当前验收状态](../../../docs/implementation-status.md)。
