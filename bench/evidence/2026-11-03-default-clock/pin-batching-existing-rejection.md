# Record pin batching已有否决，不重复实施

只读核对当前batchGroup View保护，成功releaseAfter recordpins可按(snapshot,channel)run聚合seq_cst fetchSub(n)，资源回收仍需readers0/pending0；cache/controlpins不纳入。中间pendingCount可保守偏高、Runtimehealth不读configpending，detach/reactivate不等待recordpins0，newretains不能被旧run吞掉。需要pins.flush->written.flush->versions.deinit before notify和异常幂等。

但完全同机制已存在2026-11-01 batch-pins：pin独立/统一两个版本总240项、32,240,000实际JSON，完整流程无推广资格且Memory多负向，source/test已冻结。当前不作为新候选。相关doc: docs/batch-accounting.md及bench/evidence/2026-11-01-batch-pins/README.md。此记录只读，不重跑既有失败，也不改变任何pending观察或queue/CRC。
