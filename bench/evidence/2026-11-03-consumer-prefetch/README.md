# Consumer next-record payload prefetch候选

在consumer `drainJournal`的per-record循环中，对下一条record payload执行`@prefetch`（read, locality 3, data），尝试隐藏mmap/heap payload读取延迟。E-core 20对A/B显示稳定小幅回退，候选撤回。

## 身份

- 源码：提交`5ace490`加本候选（未提交）；基线`/tmp/reference-kron-current` `68c06b81...`。
- 候选：`/tmp/reference-kron-prefetch` `95597f5ab9587df562fd9bed814fd6ba717a586e06dbeb825c54042aac93cd7a`。
- 变更：`src/core/runtime.zig` per-record循环首部
  `if (index + 1 < batch.len) @prefetch(batch[index + 1].payload.ptr, .{ .rw = .read, .locality = 3, .cache = .data });`
- E-core affinity `[16,18,20,22,24,26]`，runtime async P4，300k events+1k warmup，20对baseline/candidate交替。

## 结果

written中位比（candidate/baseline）：

| storage | phase | median ratio | mean | stdev |
| --- | --- | ---: | ---: | ---: |
| memory | batch | 0.9871 | 0.9839 | 0.0312 |
| memory | sampled | 0.9848 | 0.9884 | 0.0218 |
| mmap | batch | 0.9905 | 0.9891 | 0.0156 |
| mmap | sampled | 0.9880 | 1.0094 | 0.0632 |

3/4配置中位为负；mmap sampled的mean略正但median仍0.988且stdev较大。原始row见[results.jsonl](results.jsonl)。

## 决策

按预定门槛**撤回**，`src/core/runtime.zig`恢复基线。该prefetch没有带来稳定收益，额外指令/cache污染超过可能的延迟隐藏；生产无改动。

## 边界

E-core runtime frontend诊断，不是完整managed dual-topology/Foundation trial；没有durable flush或真实设备。整体“业界最佳”目标仍未完成。
