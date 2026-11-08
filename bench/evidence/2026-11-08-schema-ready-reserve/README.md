# Schema ready-reserve: remove duplicate registry validation

## 变更

`Runtime.submitSafeDestination` 在提交 schema 记录前已经调用 `resolveReadySchema(binding.reference)`：这一步在 `Registry.validateReady` 中完成 ready/marker/id/version/hash 校验，并返回规范 `Definition` 供编码使用。随后 `reserveWithSchema` / `reserveSingleProducerWithSchema` 又对同一个 reference 调用一次 `validateSchemaReady`，做第二次完全相同的 registry 查找。

本候选新增 `Journal.reserveWithSchemaReady` 与 `Journal.reserveSingleProducerWithSchemaReady`：调用方契约是“同一 submission 内已经用 `resolveReadySchema` 解析过该 reference”，reserve 只写入 slot schema reference，不再重复查找。shared async 与 SPSC 两条 reserve 路径都改用 Ready 变体。Debug 构建仍在 Ready 变体内复核一次以捕获误用；ReleaseSafe/ReleaseFast 不重复查找。

不改变公开 API、输出字节、journal 格式、CRC、三检查点、recovery、queue 预算或默认 durability。schema registry 的 entry 在 ready 后不可变，且同一调用内刚完成校验，因此跳过的是纯重复工作，不是校验本身。

## 正确性

- `zig build test -Doptimize=ReleaseSafe -j1`：所有能执行的 step 通过；`kron-journal-fuzz` 与 `kron-compression` 在 build-runner 下失败，但同一失败在 clean HEAD（`git stash` 后）复现，且两个 test binary 直接运行均全部通过（2/2、10/10），属于本机 build-runner 环境问题，与候选无关。其余 step（含 main test、logging、admission、journal coordinates、escaping tails、wire scratch、CRC segments、adapter、redaction、submission snapshot、fuzz 之前的全部步骤、compression 之后的 `test-deadline`、`test-query`）通过。
- 所有 A/B 输出由 `bench/cpp_reference/run.py::verify` 逐条解析核对完整 JSON；本报告 P1 聚焦 15 轮 × 4 配置 × 2 binary × 501,000 条 = **60,120,000** 条，筛查 9 轮 × 10 配置 × 2 binary × 101,000 条 = **18,180,000** 条，P4 聚焦 15 轮 × 4 配置 × 2 binary × 501,000 条 = **60,120,000** 条。
- Debug 构建的 Ready 变体保留复核，现有 `reserveWithSchema` 严格路径与 `SchemaNotReady`/`UnsupportedSchemaVersion` 测试不变。

## 直接 A/B

同一 host 窗口，E-core affinity `[16,18,20,22,24,26]`。before = HEAD `3a975a9` 构建的 `reference-kron-reverted4`（sha256 `e5a9243e...`），after = 本候选 `reference-kron-ready`（sha256 `f19c8c86...`）。比值大于 1 表示 after 更快；资格要求至少 5 轮、kron/peer/paired-ratio spread 均 ≤10%、95% bootstrap 区间不跨 1。

### 聚焦：500k events，15 轮，batch

| case | after | before | ratio 中位 | 95% CI | paired ratio 范围 | 资格 |
| --- | ---: | ---: | ---: | --- | --- | --- |
| spsc-memory-schema P1 | 2.137M | 2.074M | **1.0339** | 1.0263..1.0393 | 1.0116..1.0837 | **kron_leads** |
| spsc-mmap-schema P1 | 2.138M | 2.069M | **1.0398** | 1.0341..1.0418 | 1.0235..1.0562 | **kron_leads** |
| async-memory-schema P1 | 2.082M | 2.061M | 1.0058 | 0.9888..1.0365 | 0.9435..1.0612 | inconclusive（peer/paired spread 10.1%/11.7%） |
| async-mmap-schema P1 | 2.095M | 2.068M | 1.0052 | 0.9960..1.0251 | 0.9576..1.1598 | inconclusive（peer/paired spread 17.7%/20.1%） |

SPSC P1 两个存储轴均 qualified lead；async P1 方向为正但窗口噪声超过门槛。SPSC reserve 本身比 shared async 便宜，重复查找占单条成本更高，因此收益在 SPSC 上可测。

### P4 回归检查

| case | after | before | ratio 中位 | 95% CI | 资格 |
| --- | ---: | ---: | ---: | --- | --- |
| async-memory-schema P4 | 2.979M | 2.935M | 1.0126 | 1.0074..1.0167 | inconclusive（kron spread 15.0%，稳定性门槛未过） |
| async-mmap-schema P4 | 2.966M | 2.925M | 1.0072 | 0.9916..1.0190 | inconclusive（peer spread 25.2%） |
| spsc-memory-schema P4 | 2.562M | 2.557M | 1.0046 | 0.9948..1.0153 | inconclusive（spread 3.8%–4.9%，CI 跨1） |
| spsc-mmap-schema P4 | 2.574M | 2.570M | 1.0051 | 0.9893..1.0071 | inconclusive（spread 4.2%–5.8%，CI 跨1） |

P4 四轴中位全部为正，无 qualified negative；async-memory 的 CI 不跨 1 但 kron run spread 15% 超过稳定性门槛，按 inconclusive 记录。P4 producer 不是唯一瓶颈，收益小于 SPSC P1。

### 筛查：100k events，9 轮，全部 schema 配置

10 个配置（async/SPSC × memory/mmap × P1/P4 batch + async P1 sampled）全部 inconclusive；中位 0.9801–1.0305，无 qualified negative。该轮用于确认方向与选择聚焦配置，不作为最终资格。原始行见 `screening/results.jsonl`。

## Instructions

`perf stat -e instructions`，同一 E-core affinity，交替 5 次取中位：

| 配置 | before | after | 变化 | 每条记录 |
| --- | ---: | ---: | ---: | ---: |
| async-memory-schema P1 batch，100k | 997.02M | 992.17M | **−0.49%** | ≈ −48 |
| spsc-memory-schema P1 batch，500k | 5270.74M | 5225.07M | **−0.87%** | ≈ −91 |

instructions 下降与“每条记录少一次 registry 查找”一致；SPSC 的单条总成本更低，因此相对降幅更大，与其 qualified 吞吐收益方向一致。async P1 的指令降幅约 0.5%，低于窗口可分辨阈值，A/B 保持 inconclusive。

## 边界

- 仅移除同一 submission 内的第二次 ready 校验；第一次 `resolveReadySchema`（ready/marker/id/version/hash）与 `validateShape`、值树校验、CRC、commit、consumer peek/release 校验全部保留。
- Ready 变体是 crate 内部热路径 API，文档写明调用方契约；Debug 构建复核，误用会在测试中暴露。
- 默认 durable/CRC/recovery、journal 格式、输出字节与 queue 预算未改变。

## 原始数据

- [manifest.json](manifest.json)：host/load、git HEAD、diff sha256、binary sha256、A/B 参数与核验计数。
- [ab-p1/results.jsonl](ab-p1/results.jsonl)：P1 聚焦 4 配置 × 15 轮 × 2 binary（120 次）。
- [ab-p4/results.jsonl](ab-p4/results.jsonl)：P4 聚焦 4 配置 × 15 轮 × 2 binary（120 次）。
- [screening/results.jsonl](screening/results.jsonl)：筛查 10 配置 × 9 轮 × 2 binary（180 次）。
