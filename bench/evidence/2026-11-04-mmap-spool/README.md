# mmap spool + writer output backend (candidate smoke)

## 设计

单 producer 直接把最终 JSON 渲染进 file-backed `MAP_SHARED` 映射；一个 writer 线程每累计约 1MiB 用 `msync(MS_ASYNC)` 调度脏页回写，`flush(.written)` 只等待最后一次异步 msync，`shutdown` 把文件截断到已渲染字节数。没有 journal/CRC/recovery/ring handoff/consumer；默认 durable Runtime 不变。

- `candidate/mmap_spool.zig`：候选 Runtime，使用 `src/platform/mapping.zig`；
- `candidate/spool_reference.zig`：benchmark reference，warmup 记录编号 `events..events+warmup`，与 harness 的 `warmup_bytes` 约定一致；
- `candidate/production.patch`：候选所需的 `Mapping.syncMappedRangeAsync`、Linux `msync(MS_ASYNC)` 与 `src/root.zig` 导出；生产源码已恢复基线，本候选未进入生产。

容量按 `(events+warmup)*512 + 4MiB` 计算；100k+1k 记录实测输出 30,239,395B，映射容量约 55MiB。

## Smoke 结果

同一 P-core（`taskset -c 2`），100k events + 1k warmup，5 trials；完整 JSON 逐条核验：

| 指标 | 5 trials |
| --- | ---: |
| written_records_per_sec | **3,373,779 / 3,402,789 / 3,460,420 / 3,471,710 / 3,478,661** |
| producer_wall_ns | 26.82–27.35ms |
| flush_ns | 2.9–3.3µs |
| shutdown_ns | 1.25–1.47ms |
| init_ns | 11.3–23.8ms |
| artifact_bytes | 30,239,395 |
| written_bytes | 29,936,502 |
| records verified | 101,000/101,000，5/5 |

逐 trial 的 sha256、行数和 warmup/written 字节核对见[verification.txt](verification.txt)；原始 stdout 见[smoke.jsonl](smoke.jsonl)。

对照（不同窗口，仅作方向性参考，不构成排名）：

- 现有 text fast path P1 async memory 1.89M–2.23M、SPSC memory 1.83M–2.10M、async mmap 2.03M–2.30M（[text fast path](../2026-11-04-text-fast-path/README.md)）；
- Foundation/tracing mmap P1 2.4M–2.97M（tracing 为 peer lead 的最大剩余差距）。

同一 `MS_SYNC` 版本（等待真实回写）只有 0.06M–1.23M（带 writer）或 0.26M–0.87M（无 writer）；差距全部来自 durability barrier，而不是 render。`MS_ASYNC` 版本不等待磁盘回写，只保证 dirty page 对读者可见，符合 benchmark 的非 durable `written` 边界。

## 边界

- 这是**单拓扑、单 CPU affinity、5 trials smoke**，没有同窗口 Foundation/tracing A/B，不能 qualified，也不能更新排名。
- `written` 是非 durable 边界；进程崩溃可能留下部分尾部记录。没有 journal/recovery，不能替代 durable mmap 排名。
- 映射容量约 55MiB，明显大于默认 256-slot queue；这是用内存换 producer/consumer 解耦，必须作为 opt-in fast mode 记录资源预算。
- harness 当前对 `storage="mmap"` 要求 `has_process_crash_recovery=true`，该候选不满足；接入 harness 需要新的 strategy/storage 标签和独立验证分支。

## 下一步

1. 用同一窗口、同一 affinity 跑 P1 `batch/sampled` vs Foundation/tracing 的 5 轮 A/B，按既定 spread/CI 门槛判定。
2. 若方向成立，接入 opt-in fast mode：容量/`idle`/`MS_ASYNC` 可配置，增加容量耗尽、尾部部分记录、flush/shutdown 幂等与重启截断测试；durable 模式使用 `MS_SYNC` + fsync，不与 `written` 混淆。
3. 评估 55MiB 映射预算是否可接受；若不可接受，需要分块扩展/滚动 spool，而不是缩小到会阻塞 producer 的容量。
