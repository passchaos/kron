# text fast path with capture tree_validated reuse

## 配置

生产 `text_format=true` fast path（`verify_crc=false`、单 route JSON、memory 或 `recover=false` mmap、无 journal recovery）；producer 渲染最终 JSON，consumer 直接写出。本轮在 `Logger.captureAndSubmit` 的 empty-context/no-format_args 路径复用 `appendFields` 的完整 tree 验证，renderer 不再重复 `validateEvent`。

E-core `[23,25,27,29,31,21]`，100k+1k，5 rounds，120 trials，逐条核验 **12,120,000** 条完整 JSON。

## 结果

| 配置 | kron batch | Foundation | tracing | 配对结果 |
| --- | ---: | ---: | ---: | --- |
| async-memory P1 | **2.307M** | 1.789M | 2.203M | vs Foundation 1.286 qualified；vs tracing **1.038 qualified**（CI 1.009..1.092） |
| async-memory P1 sampled | 2.194M | 1.696M | 1.978M | 中位 1.293/1.110，但 sampled spread 24.7% → inconclusive |
| async-mmap P1 | 2.454M | 2.129M | 2.748M | vs Foundation 1.165 inconclusive；vs tracing **0.888 peer lead**（CI 0.872..0.930） |
| async-memory P4 | 4.015M | 2.208M | 1.980M | 中位 1.830/1.969，但 peer/窗口 spread 12.9%/105% → inconclusive |
| async-mmap P4 | 3.949M | 2.631M | 3.083M | 中位 1.544/1.281，但 spool/peer spread 13–26% → inconclusive |

完整 paired ratio、CI 与逐条 JSON 核验在[analysis.json](analysis.json)/[comparison.md](comparison.md)/[results.jsonl](results.jsonl)。

## 结论

- `tree_validated` 复用给生产 text fast path 带来 **P1 memory batch 对两个前端的 qualified lead**（1.286/1.038）。
- P1 mmap 仍落后 tracing（0.888 peer lead）；这是当前最大的生产 fast path 缺口。
- P4 batch 中位 3.95–4.02M，领先明显，但本窗口 spread 使配对保持 inconclusive。
- sampled 的 spread 主要来自 per-call 计时窗口噪声；batch 更稳定。

## 边界

- text fast path 是 opt-in、无 recovery、`verify_crc=false`；默认 durable/CRC/三检查点/recovery 不变。
- P1 mmap 的 tracing peer lead 不能被 P4 或 memory 的 lead 抵消；整体仍不是“全面超过”。
- spool 候选在 P1 mmap 的 E-core 中位已到 1.07–1.09（r3 3/4 qualified），但它仍是 evidence-only，未进入生产。
