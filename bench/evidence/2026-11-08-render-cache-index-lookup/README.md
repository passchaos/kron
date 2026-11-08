# Rejected: direct render-cache index lookup

## 候选

`renderCacheFor(journal)` 在每次 producer 提交和每次 `drainJournal` 调用时线性扫描 `render_journals`。SPSC P4 有 4 个 channel，`drainAvailable` 每轮对 4 个 journal 各扫一次，producer 每记录也扫一次；profile 中该扫描约占 `drainJournal` self 的 10%。

候选按“shared journal 在 index 0、registry channel 按 `activeJournals()` 顺序”直接计算 cache index，并在指针匹配时返回；公共 API 传入非本 channel journal 时回退原扫描。`drainAvailable` 直接把 cache 传给 `drainJournal`，消除 consumer 侧扫描。

## 结果（E-core，500k events，5 轮，cache on）

before = `reference-kron-fixedout2`（sha256 `d1e6da7d...`），after = `reference-kron-cacheidx`（sha256 `5f880ece...`）。

| case | after | before | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| spsc-memory-schema P1 | 2.280M | 2.261M | 1.0081 | 0.9982..1.0214 | inconclusive（spread 1.3%–2.6%，CI 跨1） |
| spsc-memory-schema P4 | 2.556M | 2.577M | 0.9916 | 0.8381..0.9978 | inconclusive（kron spread 16.9%） |
| spsc-mmap-schema P1 | 2.257M | 2.259M | 0.9980 | 0.8497..1.0123 | inconclusive（spread 28%–40%） |
| spsc-mmap-schema P4 | 2.561M | 2.584M | 0.9973 | 0.9589..1.0030 | inconclusive（spread 2.9%–4.4%，CI 跨1） |
| async-memory-schema P1 | 2.300M | 2.240M | 1.0256 | 0.9256..1.0480 | inconclusive（paired spread 11.9%） |
| async-memory-schema P4 | 2.959M | 2.941M | 0.9890 | 0.5843..1.0467 | inconclusive（kron spread 44.6%） |
| async-mmap-schema P1 | 2.242M | 2.216M | 1.0044 | 0.9900..1.0455 | inconclusive（spread 3.7%–5.5%，CI 跨1） |
| async-mmap-schema P4 | 2.949M | 3.003M | 1.0003 | 0.9574..1.0498 | inconclusive（spread 3.4%–9.2%） |

稳定窗口的 SPSC P4 mmap（spread 2.9%–4.4%）为 0.9973，async mmap P1/P4 为 1.0044/1.0003；没有 qualified lead，也没有 qualified negative。profile 中扫描的热度没有转化为可测吞吐，说明该循环的指令/分支成本已被流水线隐藏，或 `drainJournal` 的 29% self 主要来自其它内联工作。

## 决定

候选撤回，`src/core/runtime.zig` 恢复到 `a2af5d1`。生产保持原 `renderCacheFor` 指针扫描。

## 原始数据

- [results.jsonl](results.jsonl)：8 配置 × 5 轮 × 2 binary（80 次，4,008 万条完整 JSON）。
- [manifest.json](manifest.json)：host/load、binary sha256、A/B 参数与核验计数。
