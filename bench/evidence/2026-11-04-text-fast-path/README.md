# Volatile text fast path

## 设计

opt-in `MemoryQueueOptions.text_format = true`（同时要求 `verify_crc = false`）：

- producer：capture/admission 后把最终 JSON 渲染进 memory queue slot；slot payload 前20字节是capture-time route generation/fingerprint/channel，后面是完整JSON行。
- consumer：读取slot header选择route snapshot，直接 `writeRecord`，不再decode/render，也不做slot CRC。
- 约束：shared async或SPSC、单route、JSON、memory queue或`recover=false`的mmap journal；无journal recovery；默认durable路径不变。
- 输出 parity 测试：固定clock/session下，text路径与durable deferred路径的inline/schema输出byte-identical（async与SPSC）。

该模式与Foundation/tracing的“无恢复”语义对齐；默认CRC/三检查点/recovery仍保留给durable模式。

## Async A/B（E-core，5轮，text vs Foundation/tracing）

| case | peer | ratio | 95% CI | kron | peer |
| --- | --- | ---: | --- | ---: | ---: |
| p1-batch-inline | foundation_tracing | 1.0520 | 1.033..1.185 | 2.230M | 2.148M |
| p1-batch-inline | foundation | 1.2312 | 1.229..1.468 | 2.230M | 1.789M |
| p1-sampled-inline | foundation | **1.2572** | 1.178..1.260 | 2.164M | 1.721M |
| p1-sampled-inline | foundation_tracing | 1.0538 | 0.999..1.119 | 2.164M | 2.005M |
| p1-batch-schema | foundation | 1.1482 | 0.724..1.245 | 2.081M | 1.822M |
| p1-sampled-schema | foundation | **1.1010** | 1.092..1.183 | 1.886M | 1.702M |
| p1-sampled-schema | foundation_tracing | 0.9478 | 0.912..1.005 | 1.886M | 1.990M |
| p4-batch-inline | foundation | 1.7112 | 1.641..1.872 | 3.963M | 2.286M |
| p4-batch-inline | foundation_tracing | 1.7848 | 1.689..1.970 | 3.963M | 2.181M |
| p4-batch-schema | foundation | **1.6817** | 1.647..1.757 | 3.836M | 2.255M |
| p4-sampled-inline | foundation | **1.6931** | 1.678..1.799 | 3.860M | 2.274M |
| p4-sampled-schema | foundation | 1.6119 | 1.254..1.741 | 3.839M | 2.329M |
| p4-sampled-schema | foundation_tracing | 1.6773 | 1.327..1.805 | 3.839M | 2.281M |

- P4 text 3.84M–3.96M，对Foundation/tracing中位1.61–1.78；部分轴qualified lead，其余因窗口spread inconclusive。
- P1 text 1.89M–2.23M：对Foundation中位1.10–1.26，对tracing中位0.95–1.05；没有qualified negative。

## SPSC A/B（E-core，5轮，text vs Foundation/tracing）

| case | peer | ratio | 95% CI | kron | peer |
| --- | --- | ---: | --- | ---: | ---: |
| p4-batch-inline | foundation_tracing | 2.3234 | 1.721..13.035 | 5.057M | 2.194M |
| p4-batch-schema | foundation_tracing | **2.2561** | 2.168..2.298 | 4.943M | 2.233M |
| p4-batch-schema | foundation | **2.1683** | 2.095..2.275 | 4.943M | 2.302M |
| p4-sampled-inline | foundation | **2.1320** | 2.035..2.200 | 5.003M | 2.364M |
| p4-sampled-schema | foundation | 2.0601 | 1.678..2.064 | 4.804M | 2.330M |
| p1-sampled-inline | foundation | **1.1364** | 1.116..1.149 | 1.909M | 1.695M |
| p1-sampled-inline | foundation_tracing | 0.9741 | 0.954..0.982 | 1.909M | 1.997M |
| p1-sampled-schema | foundation_tracing | 0.8932 | 0.888..0.916 | 1.833M | 2.018M |

- **SPSC P4 text 4.80M–5.06M**，对 Foundation/tracing 中位 **2.06–2.32**，多个 qualified lead。
- SPSC P1 text 1.83M–2.10M：对 Foundation 1.08–1.18（部分 lead），对 tracing 0.89–0.97（sampled 两轴 peer lead）；P1 tracing 差距仍在。

## Mmap A/B（E-core，5轮，async text vs Foundation/tracing）

| case | peer | ratio | 95% CI | kron | peer |
| --- | --- | ---: | --- | ---: | ---: |
| p4-batch-inline | foundation_tracing | 1.3396 | 0.852..1.410 | 3.853M | 2.827M |
| p4-batch-schema | foundation_tracing | 1.2655 | 1.222..1.694 | 3.500M | 2.539M |
| p4-batch-schema | foundation | 1.1709 | 1.090..1.521 | 3.500M | 2.814M |
| p4-sampled-inline | foundation | 1.4000 | 1.316..1.587 | 4.039M | 2.853M |
| p4-sampled-inline | foundation_tracing | 1.3277 | 1.303..1.692 | 4.039M | 2.929M |
| p4-sampled-schema | foundation | 1.3856 | 1.210..1.411 | 3.828M | 2.867M |
| p1-batch-inline | foundation | **1.0916** | 1.043..1.106 | 2.304M | 2.160M |
| p1-sampled-inline | foundation | **1.1166** | 1.049..1.127 | 2.146M | 1.922M |
| p1-sampled-inline | foundation_tracing | 0.8662 | 0.815..0.887 | 2.146M | 2.478M |
| p1-batch-inline | foundation_tracing | 0.8005 | 0.751..0.844 | 2.304M | 2.968M |
| p1-batch-schema | foundation_tracing | 0.7225 | 0.671..0.832 | 2.027M | 2.805M |

- **P4 mmap text 3.50M–4.04M**，对 Foundation/tracing 中位 **1.09–1.40**，全部因spread inconclusive但中位领先。
- P1 mmap text 2.03M–2.30M：对 Foundation 0.94–1.12（部分 lead），对 tracing 0.72–0.87（peer lead）；**tracing mmap P1 仍是最大剩余差距**。

原始行见[async results](results.jsonl)、[SPSC results](spsc/results.jsonl)与[mmap results](mmap/results.jsonl)。

## 门禁

- `test`：**65/65 steps、765/766 tests（1项skip）**，success。
- `verify-local`：**159/159 steps、799/800 tests（1项skip）**，`verify-local success`。

## 边界

text模式是volatile，不提供crash recovery；默认durable路径仍是CRC/journal/recovery。A/B绑定当前E-core窗口，host load见[host-load.txt](host-load.txt)。binary身份见[binaries.sha256](binaries.sha256)与[spsc/binary.sha256](spsc/binary.sha256)，源码见[candidate.patch](candidate.patch)。
