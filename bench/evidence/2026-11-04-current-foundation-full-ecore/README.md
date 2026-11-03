# 保留批量确认后的E-core完整Foundation矩阵

## 身份

- 源码：提交`e2934f8`（batch consumer written acknowledgement）。
- kron binary `1778caa66fc7635488b8be90da9d921932328528ea8266b2f7eac90ec850d19a`。
- Foundation binary `9ba6ea69...`、tracing binary `fc861002...`；harness/source hash见[manifest.json](manifest.json)。
- E-core affinity `[16,18,20,22,24,26]`；240 trials，逐条核验**24,240,000**条完整JSON。

## 结果

资格仍为`target_not_met_in_selected_cases`。written比较：**9 kron lead、20 peer lead、35 inconclusive**。

- P1 batch/sampled对Foundation memory四组均为kron lead：
  - async-memory-inline 1.068 / 1.137
  - async-memory-schema 1.140 / 1.183
  - spsc-memory-inline 1.093 / 1.161
  - spsc-memory-schema 1.125 / 1.191
- 对tracing P1多数inconclusive，仅`spsc-memory-schema P1 sampled` 1.020为qualified lead。
- P4仍落后：Foundation memory batch 0.773–0.908、mmap batch 0.554–0.658 peer lead；tracing P4多数inconclusive、部分peer lead。
- 初始化仍是独立差距：kron mmap init 11.6–1223ms，Foundation mmap 15.6–872ms；SPSC mmap schema P1 init 1223ms需单独处理。

完整逐轴表、置信区间和spread见[comparison.md](comparison.md)与[analysis.json](analysis.json)。

## 决策与边界

该矩阵证明批量确认把P1 memory batch/sampled从原先的混合/落后推进到对Foundation的稳定领先，但P4/mmap和tracing仍限制整体资格。矩阵只覆盖E-core；P-core需在安静窗口单独重跑，不能由本结果外推。整体“业界最佳”目标仍未完成。
