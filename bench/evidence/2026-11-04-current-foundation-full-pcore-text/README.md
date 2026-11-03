# P-core matrix with P4 text fast path

## 身份与配置

- P-core affinity `[0,2,4,6,8,10]`；240 trials、逐条核验**24,240,000**条完整JSON。
- P4 async/SPSC、memory/mmap、inline/schema 使用 `text_format` fast path；P1 使用durable路径。
- host load约150；P-core约50% idle。

## 结果

written比较 **64/64 inconclusive**（窗口spread未通过），P-core排名不能更新。P4中位：

| kron配置 | kron | Foundation/tracing |
| --- | ---: | ---: |
| async-memory batch | 3.027M | 2.05M–2.12M |
| async-memory sampled | 2.18M | 2.06M–2.11M |
| async-mmap batch | 2.784M | 2.31M–2.35M |
| async-mmap sampled | 3.076M | 2.24M–2.31M |
| spsc-memory batch | 4.139M | 2.05M–2.12M |
| spsc-memory sampled | 3.753M | 2.06M–2.11M |
| spsc-mmap batch | 4.250M | 2.32M–2.35M |
| spsc-mmap sampled | 3.832M | 2.24M–2.31M |

中位领先约1.2–1.9x，但5轮窗口的spread使全部轴inconclusive；这是P-core宿主负载限制，不是吞吐回退。

## 附带修复

矩阵暴露了 **SPSC + mmap + text_format** 的thread channel没有传播`text_format`，导致`CrcRequiredForRecovery`；已修复thread registry并新增`text queue spsc mmap matches durable deferred render`回归。修复后SPSC mmap text P4 smoke为4.977M，矩阵240/240输出通过。

## 边界

本矩阵不提供P-core排名；需要安静P-core窗口重跑。E-core text fast path的qualified结果不变。原始逐轴表见[comparison.md](comparison.md)与[analysis.json](analysis.json)。
