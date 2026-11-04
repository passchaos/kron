# mmap spool + writer output backend

## 设计

单 producer 直接把最终 JSON 渲染进 file-backed `MAP_SHARED` 映射；一个 writer 线程每累计约 1MiB 用 `msync(MS_ASYNC)` 调度脏页回写；`flush(.written)` 只等待最后一次异步 msync，`shutdown` 把文件截断到已渲染字节数。没有 journal/CRC/recovery/ring handoff/consumer；默认 durable Runtime 不变。

- `candidate/mmap_spool.zig`：最终候选 Runtime；
- `candidate/production.patch`：候选所需的 `Mapping.syncMappedRangeAsync`、Linux `msync(MS_ASYNC)` 与 `src/root.zig` 导出；
- `candidate/spool_reference.zig`：独立 smoke reference；
- `candidate/harness.patch`：`kron_reference.zig` 的 `spool` mode、`run.py`/`qualification.py` 的 spool 分支；
- 生产 `src/` 已恢复基线，本候选未进入生产。

可选 `timestamp_period`（默认 1 = 每条精确时间）：大于 1 时复用一次 clock capture，降低 producer 的 clock 读取成本；E-core 结果使用 64。

容量按 `(events+warmup)*512 + 4MiB` 计算；100k+1k 记录实测输出 30,239,395B，映射容量 55,906,304B。

## 独立 smoke

单 P-core（`taskset -c 2`），100k+1k，5 trials：written **3.374M–3.479M**，producer_wall 26.8–27.4ms，flush 2.9–3.3µs，shutdown 1.25–1.47ms；101,000/101,000 条完整 JSON 逐条核验，5/5 artifact sha256 见[verification.txt](verification.txt)、原始 stdout 见[smoke.jsonl](smoke.jsonl)。

## 同窗口 A/B（100k+1k，5 rounds）

`run.py` 现在支持 `--kron-modes=spool --kron-storages=mmap --kron-schema=off`；spool 是单 producer、非 durable、无 recovery，不能替代 durable 排名。

| 窗口 | affinity | spool batch/sampled | 结果 |
| --- | --- | --- | --- |
| `p1-ab` | P-core `[0,2,4,6,8,10]`，load 136–149 | 1.813M / 1.514M | 全部 inconclusive；中位比值 1.30/1.16（batch）、1.54/1.12（sampled） |
| `p1-ab-ecore-quiet` | E-core `[23,25,27,29,31,21]`，period 1 | 2.604M / 2.317M | tracing **peer lead** 0.961/0.969；`target_not_met_in_selected_cases` |
| `p1-ab-ecore-nowriter` | 同 E-core，无 writer 线程 | 2.564M / 2.282M | tracing peer lead 0.935/0.943；比 writer 版本更慢，撤回 |
| `p1-ab-pcore-smt` | P-core SMT `[1,3,5,7,9,11]` | 3.355M / 2.943M | sampled 两对 qualified lead（1.602/1.162）；batch 中位 1.524/1.314，但 spool spread 10.44% → inconclusive |
| `p1-ab-pcore-smt-r2` | 同上 | 3.305M / 2.904M | batch 两对 qualified lead（1.517/1.249）；sampled vs Foundation 1.515 lead；sampled vs tracing 1.176 但 peer/ratio spread 11.8%/13.6% → inconclusive |
| `p1-ab-pcore-smt-r3` | 同上 | 3.276M / 2.940M | batch vs tracing 1.287、sampled vs Foundation 1.536、sampled vs tracing 1.210 均 qualified；batch vs Foundation 1.594 但 peer spread 10.1% → inconclusive |
| `p1-ab-pcore-smt-r4` | 同上 | 3.320M / 2.929M | Foundation 两对 qualified（1.613/1.563）；tracing 两对 inconclusive（tracing spread 15.9%/17.9%） |
| `p1-ab-pcore-smt-r5` | 同上 | 3.252M / 2.928M | Foundation 两对稳定；tracing sampled spread 15.8% → inconclusive |
| `p1-ab-pcore-smt-r6` | 同上 | batch outlier | spool batch spread 97% → batch 对 inconclusive；sampled vs tracing 1.215 qualified |
| `p1-ab-pcore-smt-ts64` | P-core SMT，`timestamp_period=64` | 3.325M / 2.988M | sampled 两对 qualified（1.588/1.217）；batch 中位 1.631/1.275，但 peer batch spread 15.6%/12.8% → inconclusive |
| `p1-ab-ecore-ts64` | E-core，`timestamp_period=64` | **2.730M / 2.424M** | batch vs Foundation 1.274、batch vs tracing **1.025**、sampled vs Foundation 1.251 均 qualified；sampled vs tracing **0.998** inconclusive（CI 0.980..1.012）；所有 spread ≤4.1% |
| `p1-ab-ecore-ts64-r2` | E-core，`timestamp_period=64` | 2.816M / 2.462M | Foundation 两对 qualified（1.334/1.267）；tracing batch 1.013（CI 0.991..1.035）、sampled 1.004（CI 0.922..1.028）均 inconclusive；tracing sampled spread 10.3% |
| `p1-ab-ecore-ts128` | E-core，`timestamp_period=128` | 2.713M / 2.404M | tracing batch 单点 outlier（spread 97%）；sampled vs tracing 1.003 inconclusive；Foundation 两对 qualified |

每个窗口的完整 min/max、paired ratio、95% CI 与逐条 JSON 核验在各自目录的 `analysis.json`/`comparison.md`/`results.jsonl`。

## 结论

- **P-core**：spool 对 Foundation/tracing 有稳定的中位领先（1.2–1.6x）；sampled 两对在 r1、r3、ts64 等窗口均 qualified lead，batch 中位 1.27–1.63 但常被 peer batch spread（10–18%）卡成 inconclusive。r1–r7 中每个 pair 都至少在一个窗口 qualified lead，**没有 qualified peer lead**；没有单一窗口四对全部 qualified。
- **E-core**：period 1 时 tracing peer lead（0.96）；`timestamp_period=64` 后 batch 对 tracing 变成 qualified lead（1.025），sampled 为 0.998 parity（CI 跨 1）。这是当前最接近“P1 全面领先”的窗口，但 sampled 仍差约 0.2%。
- **TSC clock** 更慢（P-core 2.54–2.60M vs native 2.59–2.66M，init 25–26ms vs 15–30ms），未采用。
- **coarse publish**（每 64 条 publish 一次）与 per-record 版本持平（2.773M vs 2.792M median），未采用；最终候选保留 per-record release store。

## 边界与未完成

- spool 是**非 durable、无 recovery、单 producer** 的 opt-in fast mode；崩溃可能留下部分尾部记录。`flush(.durable)` 返回 `UnsupportedDurability`。
- 55.9MiB 映射远大于默认 256-slot queue；这是用内存换 producer/consumer 解耦，必须作为资源预算记录。
- `timestamp_period>1` 复用时间戳，staleness 以 clock-call 计数而非时间为界；生产化需要时间界（例如 1ms refresher）或明确文档。
- 严格“所有选中 case 全部 qualified lead”门槛仍未满足：E-core 对 tracing 为 parity（0.998–1.013，CI 跨 1）；P-core 缺一个单窗口四对全 qualified。默认 durable 路径仍未全面超过两个前端。
- 下一步：做通用 fast render 以跨过 E-core parity（specialized template 诊断曾显示 P1 +10%–23% 的 render 空间）；把 timestamp cache 改成有界时间（1ms refresher/专用线程）以保留语义；再评估 P4/durable 路径。

## 复现

```sh
git apply bench/evidence/2026-11-04-mmap-spool/candidate/production.patch
cp bench/evidence/2026-11-04-mmap-spool/candidate/mmap_spool.zig src/core/mmap_spool.zig
git apply bench/evidence/2026-11-04-mmap-spool/candidate/harness.patch
python3 bench/cpp_reference/run.py --output-dir=/tmp/spool-ab \
  --libraries=foundation,foundation_tracing,kron --events=100000 --warmup=1000 \
  --repeats=5 --producers=1 --kron-modes=spool --kron-storages=mmap \
  --kron-schema=off --kron-spool-timestamp-period=64 \
  --affinity=23,25,27,29,31,21 --discard-artifacts
python3 bench/cpp_reference/analyze.py /tmp/spool-ab
```
