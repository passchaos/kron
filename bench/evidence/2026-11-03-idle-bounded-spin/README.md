# Consumer bounded-spin idle候选

在`.sleep` idle路径中，于`worker_sleeping`/futex wait前增加256次`spinLoopHint`并检查`wake_epoch`，尝试覆盖producer burst而不完全park consumer。E-core 20对A/B全部小幅回退，候选撤回。

## 身份

- 源码：提交`fe35e56`加本候选（未提交）；基线`/tmp/reference-kron-current` `68c06b81...`。
- 候选：`/tmp/reference-kron-hybrid` `a50658efc532ef9b1cefa67e8875d403f2b0141278197c58998f9c8c62e2c41b`。
- 变更：`src/core/runtime.zig` worker idle路径，`.spin`分支不变；`.sleep`前最多256次epoch检查spin，epoch变化则直接continue drain。
- E-core affinity `[16,18,20,22,24,26]`，runtime async P4，300k events+1k warmup，20对baseline/candidate交替。

## 结果

written中位比（candidate/baseline）：

| storage | phase | median ratio | mean | stdev |
| --- | --- | ---: | ---: | ---: |
| memory | batch | 0.9793 | 0.9937 | 0.0478 |
| memory | sampled | 0.9748 | 0.9800 | 0.0661 |
| mmap | batch | 0.9949 | 0.9911 | 0.0466 |
| mmap | sampled | 0.9977 | 0.9682 | 0.1111 |

4/4配置中位为负；额外spin指令没有换来可测的wake延迟收益。原始row见[results.jsonl](results.jsonl)。

## 决策

按预定门槛**撤回**，`src/core/runtime.zig`恢复基线。该结果与既有`.spin`候选一致：P4关键路径是consumer持续格式化/写出，而不是idle wake延迟；生产保持`.sleep`。

## 边界

E-core runtime frontend诊断，不是完整managed dual-topology/Foundation trial；没有durable flush或真实设备。整体“业界最佳”目标仍未完成。
