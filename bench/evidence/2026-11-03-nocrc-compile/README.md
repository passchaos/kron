# 当前V3源码 compile-time no-CRC诊断

runtime `MemoryQueueOptions.verify_crc=false` A/B在当前窗口没有复现旧compile-time收益。本诊断改为复制源码、compile-time删除slot CRC计算（`crc_disabled=true`，commit写0、validateSlot跳过），量化当前V3源码CRC的端到端份额。该副本仅诊断，不是生产候选；默认CRC、公开选项和journal格式不变。

## E-core A/B

before=production V3 CRC（`68c0...`），after=同源码compile-time no-CRC。E-core async、memory only、P1/P4、batch/sampled、inline/schema：80 trials，逐条核验8,080,000条完整JSON。

- **23 qualified lead、0 qualified negative、29 inconclusive**。
- P1 inline batch/sampled：written 1.1416/1.1325，written+flush 1.1423/1.1346，lifecycle 1.1394/1.1290。
- P1 schema batch/sampled：1.0775/1.1021，written+flush 1.0789/1.0992，p50 1.0820。
- P4 inline batch/sampled：1.1675/1.1693，written+flush 1.1662/1.1711，p99 1.3176。
- P4 schema batch：1.0792/1.0792；P4 schema sampled仅inconclusive。

compile-time移除CRC后当前V3源码memory路径快约8%–17%，说明CRC仍是显著功能成本；runtime `verify_crc=false`的同窗口负向更可能来自运行时分支/代码布局，而不是CRC工作本身。该结果不能直接用于生产：默认CRC、三检查点和恢复契约保持；它给出CRC优化的上限，并说明跨库比较应把Foundation无CRC的队列与kron CRC/恢复成本归一化。

证据：`flow-ecore/summary.json`、`results.jsonl`、`manifest.json`；shadow源码与after binary在`.zig-cache/nocrc-compile`。整体“业界最佳”目标仍未完成。
