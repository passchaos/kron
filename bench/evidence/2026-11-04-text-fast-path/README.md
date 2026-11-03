# Volatile text fast path

## 设计

opt-in `MemoryQueueOptions.text_format = true`（同时要求 `verify_crc = false`）：

- producer：capture/admission 后把最终 JSON 渲染进 memory queue slot；slot payload 前16字节是capture-time route generation/fingerprint，后面是完整JSON行。
- consumer：读取slot header选择route snapshot，直接 `writeRecord`，不再decode/render，也不做slot CRC。
- 约束：shared asynchronous、单route、JSON、memory queue；无journal/mmap/recovery；默认durable路径不变。
- 输出 parity 测试：固定clock/session下，text路径与durable deferred路径的inline/schema输出byte-identical。

该模式与Foundation/tracing的“无恢复”语义对齐；默认CRC/三检查点/recovery仍保留给durable模式。

## A/B（E-core，5轮，cache text vs Foundation/tracing）

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
- 输出逐条核验；这是无恢复模式与无恢复前端的同语义比较，不是durable默认路径的排名。

## 门禁

- `test`：**65/65 steps、764/765 tests（1项skip）**，success。
- `verify-local`：**159/159 steps、798/799 tests（1项skip）**，`verify-local success`。

## 边界

text模式是volatile，不提供crash recovery；默认durable路径仍是CRC/journal/recovery。A/B绑定当前E-core窗口，host load见[host-load.txt](host-load.txt)。原始行见[results.jsonl](results.jsonl)，binary身份见[binaries.sha256](binaries.sha256)，源码见[candidate.patch](candidate.patch)。
