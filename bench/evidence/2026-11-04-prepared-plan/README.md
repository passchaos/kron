# General prepared JSON render plan candidate

## 候选

在`prewarmSchema`时从`Definition`构建通用`RenderPlan`：预计算safe key顺序、scope/message，渲染时跳过key escaping/generic member dispatch，只写动态值；每次submit用`matches`校验shape，不匹配则回退generic。

## A/B

P1/P4 async mmap text fast path，5轮，before=generic、after=prepared plan；inline作为control（plan不启用）。

| case | ratio | 95% CI | after | before |
| --- | ---: | --- | ---: | ---: |
| p1-batch-inline（control） | 1.0004 | 0.973..1.092 | 2.390M | 2.389M |
| p1-batch-schema | 0.9061 | 0.854..0.939 | 1.899M | 2.222M |
| p1-sampled-inline（control） | 0.9891 | 0.921..1.007 | 2.141M | 2.153M |
| p1-sampled-schema | 0.9393 | 0.905..1.001 | 1.874M | 2.005M |
| p4-batch-inline（control） | 1.0226 | 0.941..1.472 | 3.790M | 3.657M |
| p4-batch-schema | 0.8309 | 0.722..0.984 | 2.850M | 3.854M |
| p4-sampled-inline（control） | 1.0326 | 0.701..1.166 | 4.104M | 4.158M |
| p4-sampled-schema | 0.9912 | 0.699..1.023 | 3.693M | 3.691M |

schema轴出现明显回退（P1 batch 0.906、P4 batch 0.831），inline control约1.00。原因：每record的`matches`（scope/message/5 key比较）与分段metadata写入，超过了跳过key escaping的收益；specialized template的收益不能直接迁移到带安全校验的通用plan。

## 决策

候选撤回，生产恢复generic render。源码diff保留在[candidate.patch](candidate.patch)，原始行见[results.jsonl](results.jsonl)。下一步若要继续render方向，需要**shape-enforcing prepared logger**（编译期/绑定期保证shape，取消每record matches）或更激进的prepared template，而不是当前通用plan。P1 tracing mmap差距仍需其他结构性方案。
