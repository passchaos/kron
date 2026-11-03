# Specialized JSON render diagnostic

## 目的

隔离generic `common.encodeDecoded`的field-tree/escaping/dispatch成本：shadow把benchmark固定shape（5个u64字段、固定scope/message/metadata）直接写成JSON template，测render上限。

## 方法

- before：当前text fast path binary `reference-kron-text-mmap`（generic render）。
- after：同源码shadow，`encodeJson`对固定shape使用`writer.print` template；其他shape仍走generic。
- P1/P4 async mmap、inline/schema、batch/sampled，5轮，text fast path，输出逐条核验。

## 结果

| case | ratio | 95% CI | after | before |
| --- | ---: | --- | ---: | ---: |
| p1-batch-inline | 1.0982 | 1.055..1.178 | 2.548M | 2.303M |
| p1-batch-schema | 1.1264 | 1.060..1.189 | 2.412M | 2.232M |
| p1-sampled-inline | 1.2307 | 1.118..1.246 | 2.429M | 1.986M |
| p1-sampled-schema | 1.0763 | 0.972..1.126 | 2.223M | 2.044M |
| p4-batch-inline | 1.0186 | 0.994..1.088 | 4.194M | 4.132M |
| p4-batch-schema | 1.0574 | 0.733..1.118 | 3.988M | 3.772M |
| p4-sampled-inline | 1.0383 | 0.861..1.273 | 4.151M | 3.954M |
| p4-sampled-schema | 1.0151 | 0.911..1.056 | 3.708M | 3.708M |

全部因spread保持inconclusive，但P1中位提升**10%–23%**，P4约1%–6%；无qualified negative。P1 text-mmap从2.30M到2.55M，P1 schema从2.23M到2.41M，仍低于tracing mmap 2.4M–2.97M，但差距缩小。

## 决策与下一步

generic render是P1差距的显著组成；benchmark-specific template不作为生产。下一候选应实现**通用prepared fast renderer**：在`prewarmSchema`/固定shape时预计算key顺序、类型和JSON分隔，只渲染动态值，跳过generic field-tree/escaping/dispatch。需保持schema/redaction/escape语义，并用同shape的完整JSON oracle验证。

shadow patch见[specialized-render.patch](specialized-render.patch)，原始行见[results.jsonl](results.jsonl)，binary身份见[binaries.sha256](binaries.sha256)。
