# Rejected: consumer schema definition cache

## 候选

`Runtime.drainJournal` 每条记录都调用 `journal.resolveReadySchema(record.schema_ref)`，对同一个 schema reference 重复做 ready/marker/id/version/hash 校验。候选在 `drainJournal` 内缓存最后一次 `(reference, Definition)`，连续记录命中时直接复用；registry definition 在 ready 后不可变，因此缓存生命周期限定在一次 drain 调用内。

```zig
var cached_reference: ?schema_module.Ref = null;
var cached_definition: ?schema_module.Definition = null;
...
const definition: ?schema_module.Definition = if (record.schema_ref) |reference| blk: {
    if (cached_reference) |cached| if (cached.id == reference.id and cached.version == reference.version and std.mem.eql(u8, &cached.hash, &reference.hash))
        break :blk cached_definition.?;
    const resolved = try journal.resolveReadySchema(reference);
    cached_reference = reference;
    cached_definition = resolved;
    break :blk resolved;
} else null;
```

## 结果（E-core，500k events，5 轮，cache on）

before = `reference-kron-fixedout2`（sha256 `d1e6da7d...`），after = `reference-kron-defcache`（sha256 `94567995...`）。

| case | after | before | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| async-memory-schema P1 | 2.297M | 2.226M | 1.0006 | 0.9598..1.0499 | inconclusive |
| async-mmap-schema P1 | 2.246M | 2.222M | 1.0094 | 1.0011..1.7910 | inconclusive（peer spread 44.6%） |
| async-memory-schema P4 | 2.888M | 3.002M | 0.9621 | 0.9501..3.7365 | inconclusive（peer spread 76.6%） |
| async-mmap-schema P4 | 2.873M | 3.019M | **0.9425** | 0.9343..0.9602 | **peer_leads**（spread 2.8%–3.9%） |

P4 mmap 是稳定回退（−5.7%，CI 不跨 1），P4 memory 中位也为负但窗口噪声过大；P1 方向中性到小幅正。缓存局部 `Definition`（约 160B）的复制与 `drainJournal` 栈布局成本超过了省下的 registry 查找，尤其影响 P4 consumer 关键路径。

## 决定

候选撤回，生产保持逐条 `resolveReadySchema`。`src/core/runtime.zig` 已恢复到提交 `2b3f123`。该实验说明 consumer 侧的 schema lookup 已不是可安全移除的纯冗余；若要继续降低 consumer 成本，需要改变 `Definition` 的传递方式（指针）或 render 路径，而不是在现有按值 API 上缓存。

## 原始数据

- [results.jsonl](results.jsonl)：4 配置 × 5 轮 × 2 binary（40 次，2,004 万条完整 JSON）。
- [manifest.json](manifest.json)：host/load、binary sha256、A/B 参数与核验计数。
