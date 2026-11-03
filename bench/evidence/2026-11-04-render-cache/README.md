# Producer-rendered JSON cache

## 变更

新增opt-in `render_cache`：producer在提交binary journal前，用capture-time route snapshot把JSON渲染到按journal sequence直接映射的volatile缓存；consumer命中时直接写出，未命中或恢复时仍走原deferred decode+render。

- `RenderCache`：`capacity == journal.capacity`，每slot `render_cache_record_bytes`；producer claim → render → publish（release store），commit失败或render失败时abort；consumer lookup（acquire load）→ 写出 → clear。
- journal格式、binary CRC、三检查点、recovery、queue capacity不变；缓存是volatile，恢复时为空并自动回退。
- 仅支持shared asynchronous journal、单route、JSON（inline与schema）；SPSC/multi-route不启用。
- 默认`render_cache=false`；`Logging.Route.render_cache`与benchmark `--render-cache=true`可显式开启。

## 正确性

- `zig build test -Doptimize=ReleaseSafe -j1`：**65/65 steps、761/762 tests（1项skip）**，success。
- `zig build verify-local -Doptimize=ReleaseSafe -j1`：**159/159 steps、795/796 tests（1项skip）**，`verify-local success`。
- `test-integration` 13/13、`test-async-storage` 10/10、`test-configurations` 14/14。
- 新增`render cache output matches deferred render for inline and schema`：固定clock/session下，inline与nested schema的输出与deferred路径byte-identical。
- 两个E-core完整矩阵各逐条核验24,240,000条完整JSON；cache-on路径的输出通过同一`verify`。

## 性能

安静窗口的runtime A/B（同一binary，cache off/on，P4 async inline，7轮）：

| case | written ratio | 95% CI | cache-on | cache-off | 资格 |
| --- | ---: | --- | ---: | ---: | --- |
| p4-memory-batch | 1.6269 | 1.5899..1.7030 | 2.913M | 1.790M | kron_leads |
| p4-memory-sampled | 1.5766 | 1.5102..1.6524 | 2.849M | 1.807M | kron_leads |
| p4-mmap-batch | 1.6133 | 1.4885..2.0800 | 2.923M | 1.727M | inconclusive |
| p4-mmap-sampled | 1.5142 | 1.4767..1.6495 | 2.768M | 1.817M | inconclusive |
| p1-memory/mmap | 1.02–1.13 | 多数跨1 | 1.84–2.14M | 1.77–1.89M | inconclusive |

P1在cache-on时producer承担render，可能从~1.9M回退到~1.74M；因此cache不默认开启，benchmark只对P4 async inline启用。

schema route也已验证：producer用同一`common.encodeDecoded`渲染schema event，输出通过`verify`。P4 async schema A/B（7轮，cache off/on）：

| case | written ratio | 95% CI | cache-on | cache-off |
| --- | ---: | --- | ---: | ---: |
| p4-memory-batch | 1.4018 | 1.3824..1.5068 | 2.630M | 1.878M |
| p4-memory-sampled | 1.4008 | 1.3893..1.4505 | 2.690M | 1.896M |
| p4-mmap-batch | 1.4597 | 1.3321..1.4825 | 2.712M | 1.885M |
| p4-mmap-sampled | 1.5096 | 1.4909..1.5204 | 2.886M | 1.894M |

四组均因spread/区间保持inconclusive，但中位增益1.40–1.51，且没有qualified negative；原始行见[schema results](schema/results.jsonl)。

当前host负载较高时的managed A/B（P4 async inline，7轮）比值为1.2484/1.4170/1.4845/1.5260，但paired spread/区间均未通过10%门槛，全部inconclusive；没有qualified negative。

两个E-core完整矩阵（cache对所有async inline开启 / 仅P4开启）均在该高负载窗口运行，分别为1 lead/12 peer/51 inc与0 lead/3 peer/61 inc；绝对吞吐低于安静窗口，不能用于更新跨库排名。原始行见[runtime results](runtime/results.jsonl)、[managed results](managed/results.jsonl)，完整矩阵见[all-async](../2026-11-04-current-foundation-full-ecore-render-cache/comparison.md)与[P4-only](../2026-11-04-current-foundation-full-ecore-render-cache-p4/comparison.md)。

## 决策与边界

保留为opt-in fast path；生产默认仍是batch-ack deferred render。安静窗口的P4 memory两轴已qualified lead，mmap两轴中位1.51–1.61但因spread保持inconclusive；需要安静窗口的完整P-core/E-core矩阵才能更新跨库排名。整体“业界最佳”目标仍未完成。
