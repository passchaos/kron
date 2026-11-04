# P-core text fast path raw window (noisy)

## 配置

生产 `text_format=true` fast path + `tree_validated` capture；P-core SMT `[1,3,5,7,9,11]`，100k+1k，5 rounds，120 trials，逐条核验 12,120,000 条完整 JSON。

## 结果

本窗口 peer/spool spread 很大，全部配对 inconclusive，不能用于排名：

- P4 async-memory batch/sampled：3.442M / 3.637M；Foundation 2.157M/2.189M、tracing 2.203M/2.107M（中位领先，但 spool spread 10%–25%）。
- P4 async-mmap batch/sampled：3.419M / 3.549M；Foundation 2.387M/2.457M、tracing 2.368M/2.348M（中位领先，但 spread 12%–24%）。
- P1 async-memory：1.995M / 1.938M；tracing 2.698M/2.493M（本窗口落后，且 spread 11%–19%）。
- P1 async-mmap：2.016M / 1.830M；tracing 2.555M/2.389M（本窗口落后）。
- Foundation memory sampled spread 94.9%、tracing mmap batch 23.7%、tracing mmap sampled 14.7%。

## 结论

这是**噪声窗口的原始证据**，不是排名：P4 中位领先明显，但 P1 数字被宿主负载压低（同一生产路径在 E-core 稳定窗口为 P1 memory batch 2.307M、对 tracing 1.038 qualified）。完整 spread/CI 见[analysis.json](analysis.json)/[comparison.md](comparison.md)/[results.jsonl](results.jsonl)。
