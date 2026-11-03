# Queue capacity诊断：256 vs 512/1024

在空闲E-core上测试queue slots对kron与Foundation完整流程吞吐的影响，判断是否应把默认capacity从256提高。结论：双方都受益，但Foundation在memory上受益更多，相对差距未缩小，因此不修改默认值。

## 身份与窗口

- 源码：提交`a356440`；生产未改。
- kron reference binary：`68c06b8109fad63fc8f345ea68882d6ad478b25198268bd3b2287be3a0590094`（runtime frontend、explicit portable）。
- Foundation reference：`9ba6ea69a875d18d84251b166e8f3cc7569a133abc5a6c76dff255c134d17868`（`2026-11-03-current-foundation-full-ecore/reference-foundation`）。
- E-core affinity `[16,18,20,22,24,26]`，300k events+1k warmup，runtime/foundation producer_format、metadata=full。

## Kron 256 vs 512

8配置×10对（300k events），written中位比（512/256）：

| storage | P | phase | median ratio | mean |
| --- | ---: | --- | ---: | ---: |
| memory | 1 | batch | 1.0125 | 0.9775 |
| memory | 1 | sampled | 1.0204 | 1.0201 |
| memory | 4 | batch | 1.0495 | 1.0446 |
| memory | 4 | sampled | 1.0354 | 1.0261 |
| mmap | 1 | batch | 1.0240 | 1.0230 |
| mmap | 1 | sampled | 1.0234 | 1.0192 |
| mmap | 4 | batch | 1.0430 | 1.0435 |
| mmap | 4 | sampled | 1.0546 | 1.0641 |

另有20对P4 mmap batch 500k事件：median ratio 1.0419、mean 1.0341、stdev 0.0638，17/20对为正。原始row见[kron-256-vs-512-matrix.jsonl](kron-256-vs-512-matrix.jsonl)与[kron-256-vs-512-p4-mmap-batch.jsonl](kron-256-vs-512-p4-mmap-batch.jsonl)。

## Foundation 256 vs 512

P4×10对（300k events）：

| storage | phase | median ratio | mean |
| --- | --- | ---: | ---: |
| memory | batch | 1.0958 | 1.1012 |
| memory | sampled | 1.0887 | 1.0910 |
| mmap | batch | 0.9999 | 1.0170 |
| mmap | sampled | 1.0319 | 1.0529 |

原始row见[foundation-256-vs-512.jsonl](foundation-256-vs-512.jsonl)。

## 256 vs 1024

P4 batch×5对：

| library | storage | median ratio (1024/256) | mean |
| --- | --- | ---: | ---: |
| kron | memory | 1.0377 | 1.0350 |
| kron | mmap | 1.0631 | 1.0510 |
| Foundation | memory | 1.1072 | 1.1192 |
| Foundation | mmap | 1.0833 | 1.0400 |

原始row见[256-vs-1024.jsonl](256-vs-1024.jsonl)。

## 决策

- 512 slots对kron绝对吞吐有约1%–5.5%收益，但Foundation在memory上约+9%–10%、mmap sampled约+3%，相对差距没有缩小甚至扩大；1024 slots同样Foundation memory收益更大。
- queue capacity是用户可配置参数，官方跨库benchmark应保持双方相同slots；把kron默认改为512/1024不会改变相对资格，只会增加journal内存与启动成本。
- 因此**不修改默认capacity**，生产保持256；该诊断仅记录配置敏感性。

## 边界

E-core runtime/foundation producer_format诊断，不是完整双拓扑managed矩阵；没有durable flush、P-core、其他queue policy或真实设备。整体“业界最佳”目标仍未完成。
