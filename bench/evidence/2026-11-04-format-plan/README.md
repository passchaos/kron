# Shape-enforcing prepared format logger

## 候选

新增`prepared.FormatLogger(Fields)`：compile-time`Fields`类型即shape contract，`RenderPlan`不再做per-record`matches`；producer text fast path直接用precomputed keys/scope/message渲染。用于schema text fast path。

## A/B

runtime frontend、P1/P4 async memory schema、text fast path，5轮，before=generic schema、after=format plan：

| case | ratio | 95% CI | plan | generic |
| --- | ---: | --- | ---: | ---: |
| p1-batch | 0.9662 | 0.529..1.126 | 2.085M | 2.037M |
| p1-sampled | 1.0339 | 0.063..2.062 | 1.589M | 1.793M |
| p4-batch | 1.2281 | 1.184..1.436 | 1.867M | 1.427M |
| p4-sampled | 0.9754 | 0.626..1.152 | 1.844M | 1.990M |

全部因spread保持inconclusive；P1/P4方向混合，没有稳定qualified lead。runtime frontend窗口噪声较大，且generic render本身已高效，shape-enforcing plan的分段写入没有稳定收益。候选撤回，生产恢复generic render。

## 决策

prepared render方向（per-record matches版与shape-enforcing版）均未取得稳定领先。下一步应转向**mmap spool + writer output backend**（与producer重叠），而不是继续在render上做plan。候选patch/results保留在[candidate.patch](candidate.patch)/[results.jsonl](results.jsonl)。
