# Text fast path: skip codec.measure

## 候选

在`text_format`模式下跳过`submitDestination`的`codec.measure`（文本渲染不需要binary size），期望省掉约4% producer cycles。`common.encodeDecoded`在`tree_validated=false`时仍会校验树，可能抵消收益。

## A/B

P1/P4 async mmap、inline/schema、batch/sampled，5轮，before=measure保留、after=measure跳过；输出逐条核验。

| case | ratio | 95% CI |
| --- | ---: | --- |
| p1-batch-inline | 1.0134 | 0.938..1.049 |
| p1-batch-schema | 1.0169 | 0.918..1.115 |
| p1-sampled-inline | 1.0171 | 0.933..1.112 |
| p1-sampled-schema | 1.0095 | 0.917..1.125 |
| p4-batch-inline | 1.0464 | 0.891..1.106 |
| p4-batch-schema | 1.0644 | 0.997..1.336 |
| p4-sampled-inline | 1.0001 | 0.826..1.088 |
| p4-sampled-schema | 1.0516 | 0.739..1.082 |

全部inconclusive，中位1.00–1.06；没有qualified lead或negative。render端的树校验抵消了measure的节省，且跳过measure可能改变无效字段的早期拒绝边界。候选撤回，生产保持measure；before/after binary身份见[binaries.sha256](binaries.sha256)，原始行见[results.jsonl](results.jsonl)，候选diff见[candidate.patch](candidate.patch)。
