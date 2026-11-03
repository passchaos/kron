# Consumer session JSON缓存候选

在fused JSON renderer中按batch缓存Runtime session的JSON字节（含>2^53 quote规则），当record header session匹配时直接写出，避免每条记录重复格式化u64 session。E-core 20对A/B只有约0.3%–1.5%中位收益，未达到qualified门槛，候选撤回。

## 设计

- `common.SessionCache`保存`value`与格式化字节；`sessionCache(session, buffer)`用现有`writeTaggedValue(.unsigned, ..., .json)`生成，保证quote/十进制字节一致。
- `wire_json.render/renderReference`增加可选cache；`encodeJsonWithAttributes`在session匹配时`writeAll(cache.bytes)`，否则回退原路径。
- Runtime consumer在每batch开始生成cache，传给`emitWireFused`；recovered record的session不匹配时自动回退。
- 公开encoder仍传`null`，行为不变。
- 新增差分test覆盖session 0/42/2^53-1/2^53/u64 max，cache与无cache输出字节相同。

## 身份

- 源码：提交`b688bb2`加本候选（未提交）；基线`/tmp/reference-kron-current` `68c06b81...`。
- 候选：`/tmp/reference-kron-session-cache` `299ba2310ada02a7abd88f0d1f80dd5068931daa993564456388cd060284a362`。
- E-core affinity `[16,18,20,22,24,26]`，runtime async P4，300k events+1k warmup，20对baseline/candidate交替。

## 结果

written中位比（candidate/baseline）：

| storage | phase | median ratio | mean | stdev |
| --- | --- | ---: | ---: | ---: |
| memory | batch | 1.0025 | 1.0020 | 0.0150 |
| memory | sampled | 1.0146 | 0.9781 | 0.1839 |
| mmap | batch | 1.0066 | 1.0039 | 0.0196 |
| mmap | sampled | 1.0038 | 1.0056 | 0.0271 |

中位方向为正但幅度约0.3%–1.5%，memory sampled mean受离群值影响为负；未达到CV/spread与完整managed dual-topology资格。原始row见[results.jsonl](results.jsonl)。

## 决策

按预定门槛**撤回**，相关源码恢复基线，生产无改动。该机制确实减少每条记录的session格式化，但收益不足以通过保留门槛；不在没有完整资格的情况下扩大API/缓存分支。

## 边界

E-core runtime frontend诊断，不是完整managed/Foundation trial；没有durable flush或真实设备。整体“业界最佳”目标仍未完成。
