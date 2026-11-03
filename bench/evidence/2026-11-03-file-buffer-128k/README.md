# FileSink buffer 64KiB vs 128KiB诊断

在空闲E-core上测试增大FileSink buffer对kron与Foundation完整流程吞吐的影响。kron有约0.4%–2.1%中位收益，Foundation基本持平/略负；收益幅度不足以改变跨库资格，默认buffer保持64KiB。

## 身份与窗口

- 源码：提交`1087423`；生产未改。
- kron 64KiB：`68c06b8109fad63fc8f345ea68882d6ad478b25198268bd3b2287be3a0590094`。
- kron 128KiB：`6d7d9a88d95927ffb5977f7c72651d15e817047c19145b4c937e34e1cbed14b9`（临时reference，`.buffer_bytes=131072`）。
- Foundation 64KiB：`9ba6ea69a875d18d84251b166e8f3cc7569a133abc5a6c76dff255c134d17868`。
- Foundation 128KiB：`eef33c84117aaaea194260f863bfbc7322edcb0b84333e92fb3458d38f6ed12b`（临时reference，`buffer_[131072]`与Quill `write_buffer_size=131072`）。
- E-core affinity `[16,18,20,22,24,26]`，300k events+1k warmup，P4，runtime/foundation producer_format、metadata=full、queue-slots=256。
- 注意：benchmark JSON的`file_buffer_bytes`字段是硬编码65536，不能反映临时128KiB实验；以二进制/source patch为准。

## Kron 64 vs 128

10对，written中位比（128/64）：

| storage | phase | median ratio | mean | stdev |
| --- | --- | ---: | ---: | ---: |
| memory | batch | 1.0166 | 1.0230 | 0.0267 |
| memory | sampled | 1.0196 | 1.0580 | 0.1184 |
| mmap | batch | 1.0213 | 1.0168 | 0.0273 |
| mmap | sampled | 1.0036 | 1.0108 | 0.0270 |

原始row见[kron-64-vs-128.jsonl](kron-64-vs-128.jsonl)。

## Foundation 64 vs 128

10对：

| storage | phase | median ratio | mean | stdev |
| --- | --- | ---: | ---: | ---: |
| memory | batch | 0.9906 | 1.2871 | 0.9796 |
| memory | sampled | 1.0020 | 1.0076 | 0.0372 |
| mmap | batch | 0.9791 | 0.9882 | 0.1182 |
| mmap | sampled | 1.0087 | 1.0125 | 0.0838 |

原始row见[foundation-64-vs-128.jsonl](foundation-64-vs-128.jsonl)。

## 决策

kron 128KiB的中位收益约0.4%–2.1%，Foundation在同配置下基本持平或略负；方向有利但幅度小、memory sampled的spread较大，未达到完整managed dual-topology/Foundation资格。默认`buffer_bytes`保持**64KiB**，生产未改；该诊断记录buffer敏感性，不作为保留依据。

## 边界

E-core runtime/foundation producer_format诊断，不是完整双拓扑managed矩阵；Foundation 128KiB是临时reference patch，不是其库默认。没有durable flush或真实设备。整体“业界最佳”目标仍未完成。

## Managed 4-way确认（P4 mmap batch）

runtime frontend的收益没有在managed路径转化为相对领先。E-core 20轮，每轮固定顺序kron64、kron128、Foundation64、Foundation128，300k events：

| 组合 | written中位 | 相对Foundation64 median ratio |
| --- | ---: | ---: |
| kron 64KiB | 1,719,447 | 0.5325 |
| kron 128KiB | 1,704,496 | 0.5270 |
| Foundation 64KiB | 3,243,475 | — |
| Foundation 128KiB | 3,062,809 | — |

kron128/Foundation64（0.5270）略低于kron64/Foundation64（0.5325）；kron128/Foundation128为0.5435。该窗口Foundation绝对吞吐明显高于前一轮，说明跨窗口绝对值不可比，必须用同轮interleave。结论不变：128KiB不带来managed相对资格，默认保持64KiB。原始row见[managed-4way-p4-mmap-batch.jsonl](managed-4way-p4-mmap-batch.jsonl)。
