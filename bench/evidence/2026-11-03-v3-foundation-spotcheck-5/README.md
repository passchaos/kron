# V3保留后的E-core Foundation抽查

这是保留V3 schema journal CRC后，用当前生产源码（`src/root.zig`）做的缩减跨库抽查，不是完整双拓扑/双schema矩阵，也不更新既有Foundation排名。

## 范围

- E-core affinity `16,18,20,22,24,26`
- async managed Logging，schema=on（kron走V3 journal），memory/mmap，P1/P4，batch/sampled
- 三个前端：Foundation + spdlog、Foundation + Rust tracing、kron
- 100,000 events、1,000 warmup、5 repeats；120 trials，逐条核验12,120,000条完整JSON
- 3-repeat先导窗口（72 trials、7,272,000条）保留在 [../2026-11-03-v3-foundation-spotcheck](../2026-11-03-v3-foundation-spotcheck/comparison.md)，资格为inconclusive

## 结果

`analyze.py`资格为 **target_not_met_in_selected_cases**：

- kron局部领先：async-memory P1 sampled vs foundation，包含关闭速度比1.041，95%区间1.033..1.101。
- peer领先（Foundation前端更快）：async-memory P1 batch vs tracing 0.848、async-memory P4 batch vs foundation 0.777、async-memory P4 sampled vs tracing 0.781、async-mmap P1 batch vs foundation 0.893。
- 其余组inconclusive；没有同时超过两个前端的完整证据。

中位吞吐（百万条/s，written+flush，3次窗口）显示kron async-memory-schema P1/P4为1.926/1.902，foundation为1.876/2.277，tracing为2.320/2.237；kron在P1接近/局部领先，在P4仍落后。p50在多数组高于两个前端，p99在P4优于Foundation但仍未全面领先tracing。初始化仍高于Foundation（memory约0.70ms vs 0.27ms，mmap约11.5–13.6ms vs Foundation memory 0.27ms/tracing mmap 330–461ms；tracing mmap初始化异常高，但该窗口只作参考）。

这些数字来自缩减抽查和当前宿主窗口，不能外推为完整矩阵或一般排名。V3保留本身由独立E-core双窗口、V3-control A/B和完整release gate支持；本抽查只说明保留后kron仍未在所选E-core schema组全面超过两个Foundation前端。

原始`results.jsonl`、`manifest.json`、`analysis.json`、`comparison.md`和两个参考binary身份保留在本目录。
