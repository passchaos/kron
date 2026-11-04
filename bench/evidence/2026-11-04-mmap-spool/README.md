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
| `p1-ab-pcore-smt-ts64-tv` | P-core SMT，ts64 + `tree_validated` | **3.671M / 3.210M** | batch vs Foundation 1.759、batch vs tracing 1.406、sampled vs Foundation 1.756 均 qualified；sampled vs tracing 1.319 但 tracing sampled spread 14.45% → inconclusive |
| `p1-ab-pcore-smt-ts64-tv-r1` | 同上 | 3.774M / 3.294M | sampled 两对 qualified（1.737/1.383）；batch 中位 1.807/1.374，但 tracing batch spread 10.2%/paired → inconclusive |
| `p1-ab-pcore-smt-ts64-tv-r2` | 同上 | 3.749M / 3.331M | sampled vs Foundation 1.818 qualified；其余因 spool batch 9.7%/paired 10.1%、tracing 11.6%/10.1% → inconclusive |
| `p1-ab-pcore-smt-ts64-tv-r3` | 同上 | 3.737M / 3.192M | batch vs Foundation 1.826、sampled vs tracing 1.330 qualified；batch vs tracing（tracing 18.1%）、sampled vs Foundation（paired 16.9%）inconclusive |
| `p1-ab-pcore8-ts64-tv` | P-core 8-thread `[1,3,5,7,9,11,13,15]` | **3.853M / 3.351M** | spool 最高中位；但 peer spread 8.6–18.1%、paired ratio 10.2–27.7%，四对全部 inconclusive |
| `p1-ab-ecore-ts64` | E-core，`timestamp_period=64` | **2.730M / 2.424M** | batch vs Foundation 1.274、batch vs tracing **1.025**、sampled vs Foundation 1.251 均 qualified；sampled vs tracing **0.998** inconclusive（CI 0.980..1.012）；所有 spread ≤4.1% |
| `p1-ab-ecore-ts64-r2` | E-core，`timestamp_period=64` | 2.816M / 2.462M | Foundation 两对 qualified（1.334/1.267）；tracing batch 1.013（CI 0.991..1.035）、sampled 1.004（CI 0.922..1.028）均 inconclusive；tracing sampled spread 10.3% |
| `p1-ab-ecore-ts128` | E-core，`timestamp_period=128` | 2.713M / 2.404M | tracing batch 单点 outlier（spread 97%）；sampled vs tracing 1.003 inconclusive；Foundation 两对 qualified |
| `p1-ab-ecore-ts64-tv` | E-core，ts64 + `tree_validated` capture | 2.919M / 2.569M | batch vs Foundation 1.424、batch vs tracing 1.072、sampled vs Foundation 1.323 均 qualified；sampled vs tracing 1.047 但 paired spread 10.4% → inconclusive |
| `p1-ab-ecore-ts64-tv-r2` | 同上 | 2.981M / 2.595M | batch vs Foundation 1.450 qualified；batch vs tracing 1.084、sampled vs tracing 1.071、sampled vs Foundation 1.387 中位领先，但 paired spread 10.9–13.5% → inconclusive |
| `p1-ab-ecore-ts64-tv-r3` | 同上 | 3.014M / 2.619M | batch vs tracing 1.086、sampled vs Foundation 1.398、sampled vs tracing 1.066 均 qualified；batch vs Foundation 1.442 中位领先，但 Foundation batch spread 15.1% → inconclusive |

每个窗口的完整 min/max、paired ratio、95% CI 与逐条 JSON 核验在各自目录的 `analysis.json`/`comparison.md`/`results.jsonl`。

## 结论

- **P-core**：spool 对 Foundation/tracing 有稳定的中位领先；tree_validated 后 P-core tv 窗口 spool batch **3.74–3.77M**、sampled **3.19–3.33M**，8-thread 窗口进一步到 **3.853M / 3.351M**；对 Foundation/tracing 中位 1.33–1.83x。6-thread tv 主窗口 3/4 qualified；r1–r3 各 2/4 qualified，每个 pair 都至少在一个窗口 qualified，**没有 qualified peer lead**；四对全 qualified 仍被 peer spread（10.1%–18.1%）卡住。8-thread 窗口虽然吞吐最高，但 peer/paired spread 更大（10.2%–27.7%），不改善 qualification。
- **E-core**：period 1 时 tracing peer lead（0.96）；`timestamp_period=64` 后 batch 对 tracing 1.013–1.025、sampled 0.998–1.004 parity。加入 `tree_validated` capture proof 后 producer render 快约 7%–8%：batch vs tracing 1.072–1.086、sampled vs tracing 1.047–1.071，中位已超过 tracing；对 Foundation 1.32–1.45 lead。r3 已拿到 3/4 qualified lead，剩下 batch vs Foundation 被 Foundation 自身 15.1% batch spread 卡住；没有任何 qualified peer lead。
- `tree_validated` 优化已通过完整 `test` **65/65 steps、766/767 tests（1 skip）**；只对 empty-context、无 format_args 的 capture 生效，`appendFields` 已证明完整 tree（key/value/node/cycle），renderer 不再重复 `validateEvent`。
- **TSC clock** 更慢（P-core 2.54–2.60M vs native 2.59–2.66M，init 25–26ms vs 15–30ms），未采用。
- **coarse publish**（每 64 条 publish 一次）与 per-record 版本持平（2.773M vs 2.792M median），未采用；最终候选保留 per-record release store。

## 边界与未完成

- spool 是**非 durable、无 recovery、单 producer** 的 opt-in fast mode；崩溃可能留下部分尾部记录。`flush(.durable)` 返回 `UnsupportedDurability`。
- 55.9MiB 映射远大于默认 256-slot queue；这是用内存换 producer/consumer 解耦，必须作为资源预算记录。
- `timestamp_period>1` 复用时间戳，staleness 以 clock-call 计数而非时间为界；生产化需要时间界（例如 1ms refresher）或明确文档。
- 严格“所有选中 case 全部 qualified lead”门槛仍未满足：E-core 对 tracing 的中位已到 1.047–1.084，但 peer/paired spread 仍会超过 10%；P-core 缺一个单窗口四对全 qualified。默认 durable 路径仍未全面超过两个前端。
- 下一步：把 timestamp cache 改成有界时间（1ms refresher/专用线程）以保留语义；继续用安静窗口把 E-core/P-core 四对 qualification 收齐；再评估 P4/durable 路径。

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
es=mmap \
  --kron-schema=off --kron-spool-timestamp-period=64 \
  --affinity=23,25,27,29,31,21 --discard-artifacts
python3 bench/cpp_reference/analyze.py /tmp/spool-ab
```
