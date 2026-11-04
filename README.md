# kron

Zig 0.16 原生日志库，提供结构化字段、同步与有界异步提交、普通文本/JSON、文件轮转、动态过滤与配置、脱敏、归档和明确的恢复边界。目标是同时降低应用开销、保持输出可读性并验证可靠性。

性能验收目标是超过 **Foundation/logging + spdlog** 和 **Foundation/logging + tracing**，在相同完整输出与完成边界下验证吞吐、生命周期和尾延迟；P-core/E-core分别测量。当前尚未全面达到，逐组结果与资格见 [前端对照](docs/cpp-comparison.md)。

当前默认 CRC、完整值域、恢复与有界队列协议保持。近期候选有局部工作量收益，但控制组或完整流程未取得保留资格，生产已恢复并增加相关边界回归。全部正负和限制见 [当前验收状态](docs/implementation-status.md) 与 [试验记录快照](docs/history/readme-performance-experiments-2026-11-03.md)。

最新 [双拓扑完整流程 profile](bench/evidence/2026-11-03-current-workflow-profile/analysis.md) 核验 800.8 万条 JSON，用于定位当前热点，不提供新的速度排名。

最新批量消费者确认候选已保留生产：连续`.written`记录的journal reclaim与snapshot pin释放合并为批次操作，逐条保留identity/slot CRC重查和late-damage成功前缀语义。E-core 16配置×5轮×2 binary核对**1,616万条JSON**，written **12 lead、0 negative、4 inconclusive**（中位1.0156–1.1074）。完整`test` 758/759、`verify-local` 792/793通过；跨库排名未更新，仍低于Foundation。证据见[batch acknowledgment](bench/evidence/2026-11-04-batch-ack/README.md)。

保留该候选后的E-core完整Foundation矩阵（240 trials、2,424万条JSON）仍为`target_not_met_in_selected_cases`：written 9 kron lead、20 peer lead、35 inconclusive。P1对Foundation memory的8个batch/sampled轴全部领先（1.068–1.191），P4 memory/mmap仍落后（0.554–0.908）；对tracing仅spsc-memory-schema P1 sampled 1.020领先。P-core需单独重跑，整体目标仍未完成。证据见[新E-core矩阵](bench/evidence/2026-11-04-current-foundation-full-ecore/comparison.md)。

render offload诊断显示consumer JSON render是P4最大单项瓶颈：生产1.830M，去掉consumer render后3.255M，producer额外render后仍有3.007M。下一候选将保留binary journal/CRC/recovery，把render结果放入独立side buffer/queue，让consumer只写出，而不是把JSON写进journal payload。见[诊断](bench/evidence/2026-11-04-render-offload-diagnostic/README.md)。

producer-rendered JSON cache已作为opt-in `render_cache`实现：producer渲染到按sequence直接映射的volatile缓存，consumer命中直接写出，未命中/恢复回退deferred；默认关闭，支持shared async与SPSC的per-journal cache、单route JSON inline/schema。安静窗口P4 memory batch/sampled为1.63/1.58 qualified lead（2.9M vs 1.8M），mmap中位1.51–1.61但因spread inconclusive；schema四组中位1.40–1.51；SPSC P4八组中位1.63–1.69（5/8 lead）。P1会回退，因此benchmark只对P4启用。完整`test` 766/767、`verify-local` 800/801通过（1项local skip）。最新E-core矩阵为12 kron lead、8 peer lead、44 inconclusive；P4 cache轴对Foundation/tracing取得1.06–1.56 lead，剩余差距集中在P1 mmap/SPSC vs tracing。安静窗口复跑为11 lead/13 peer/40 inc，P4中位async-memory 2.97M、spsc-memory 3.41M、spsc-mmap 3.44–3.52M，SPSC P4因run spread保持inconclusive但定向A/B已qualified。P-core cache矩阵在host load约126窗口重跑，written全部inconclusive；P-core P4定向A/B中位0.956–1.447、全部inconclusive但无qualified negative，需安静窗口重跑。P1 consumer profile显示cache-off时consumer render+两次CRC约占35% cycles，cache-on时producer成为瓶颈；P1对tracing的差距来自durable producer路径，下一步需要独立的opt-in volatile text-queue fast mode。见[P1 profile](bench/evidence/2026-11-04-p1-consumer-profile/README.md)、[render cache](bench/evidence/2026-11-04-render-cache/README.md)、[E-core cache矩阵](bench/evidence/2026-11-04-current-foundation-full-ecore-render-cache-all/comparison.md)、[安静窗口矩阵](bench/evidence/2026-11-04-current-foundation-full-ecore-render-cache-quiet/comparison.md)与[P-core矩阵](bench/evidence/2026-11-04-current-foundation-full-pcore-render-cache/comparison.md)。

volatile text fast path已实现为opt-in `text_format`（要求`verify_crc=false`）：producer渲染最终JSON进queue，consumer直接写出；支持memory与`recover=false` mmap、async/SPSC，无journal recovery，默认durable路径不变。固定clock/session parity测试通过（async/SPSC、inline/schema）。E-core 5轮A/B：P4 async memory 3.84–3.96M（1.61–1.78）、P4 SPSC memory 4.80–5.06M（2.06–2.32）、P4 async mmap 3.50–4.04M（1.09–1.40）；P1 async memory 1.89–2.23M（对tracing 0.95–1.05）、P1 SPSC 1.83–2.10M（对tracing 0.89–0.97）、P1 async mmap 2.03–2.30M（对tracing 0.72–0.87）。P4已明显领先，P1 tracing mmap/SPSC仍是剩余差距。见[text fast path](bench/evidence/2026-11-04-text-fast-path/README.md)。

P1 text-mmap profile显示producer约43% cycles（render约20%、submit 10.5%、reserve 4.9%、begin 4.5%、measure 4.4%），consumer约18.5%；剩余tracing mmap差距需要dedicated fast logger或mmap output backend，而不是单一轻量ring。见[profile](bench/evidence/2026-11-04-text-mmap-profile/README.md)。text fast path跳过measure候选8组5轮全部inconclusive（中位1.00–1.06），已撤回。见[measure报告](bench/evidence/2026-11-04-text-nomeasure/README.md)。独立FastRuntime候选P1为2.119M sleep/2.281M spin，未超过text fast path或缩小tracing mmap差距，已撤回；模块/参考保留在[FastRuntime报告](bench/evidence/2026-11-04-fast-runtime/README.md)，下一步做mmap spool+writer backend。specialized render诊断显示固定shape template把P1 text-mmap从2.30M提升到2.55M（P1 schema 2.23→2.41M，P1 sampled inline 1.99→2.43M），P4约1.02–1.06；全部inconclusive但P1中位10%–23%、无negative。generic render是P1差距的显著组成；下一候选是通用prepared fast renderer。见[diagnostic](bench/evidence/2026-11-04-fast-render-diagnostic/README.md)。通用prepared plan候选因每record matches/分段metadata导致schema轴回退（P1 0.906、P4 0.831），已撤回；shape-enforcing format logger也无稳定lead（P1 0.966、P4 batch 1.228、P4 sampled 0.975，全部inconclusive）。prepared render方向已基本耗尽，下一步转向mmap spool+writer backend。见[prepared plan报告](bench/evidence/2026-11-04-prepared-plan/README.md)与[format plan报告](bench/evidence/2026-11-04-format-plan/README.md)。

P-core text矩阵（240 trials、2,424万JSON）written 64/64 inconclusive；P4中位async-memory 3.03M、async-mmap 2.78–3.08M、spsc-memory 3.75–4.14M、spsc-mmap 3.83–4.25M，对Foundation/tracing约1.2–1.9x，但窗口spread未qualified。矩阵修复了SPSC+mmap+text的thread channel text flag传播并新增parity回归。见[P-core text矩阵](bench/evidence/2026-11-04-current-foundation-full-pcore-text/README.md)。

empty-context capture `tree_validated`复用已进入生产：无context、无format_args时，`appendFields`/`appendSlice`已证明完整field tree，renderer不再重复`validateEvent`。spool E-core ts64 A/B中producer render快约7%–8%：spool batch 2.92–3.01M、sampled 2.57–2.62M；对tracing batch 1.072–1.086、sampled 1.047–1.071，对Foundation 1.32–1.45；r3已拿到3/4 qualified lead，没有qualified peer lead。生产text fast path同步受益：P1 async-memory batch 2.307M vs Foundation/tracing 1.789/2.203M（1.286/1.038 qualified）；P1 async-mmap batch 2.454M vs tracing 2.748M仍为0.888 peer lead，是最大生产fast path缺口。带context/format_args的路径继续验证；默认durable/CRC/三检查点/recovery不变。完整`test` 766/767、`verify-local` 800/801通过（1项local skip）。见[mmap spool A/B](bench/evidence/2026-11-04-mmap-spool/README.md)与[text fast path A/B](bench/evidence/2026-11-04-text-fast-path-tv/README.md)。

近期 [key scratch](bench/evidence/2026-11-03-fused-key-scratch/README.md)、[短 CRC](bench/evidence/2026-11-03-short-crc/README.md)、[精确固定段 CRC](bench/evidence/2026-11-03-crc-fixed-segments/README.md)、[CAS pause](bench/evidence/2026-11-03-cas-failure-pause/README.md)、[消费校验 flat CRC](bench/evidence/2026-11-03-crc-flat-consumer/README.md)、[16行消费校验 CRC](bench/evidence/2026-11-03-crc-flat-consumer-16row/README.md) 和 [THP mmap](bench/evidence/2026-11-03-mmap-hugepage/README.md)、[consumer spin](bench/evidence/2026-11-03-consumer-spin/README.md)、[producer-format](bench/evidence/2026-11-03-producer-format/README.md)、[mutex reserve](bench/evidence/2026-11-03-mutex-reserve/README.md)、[async file sink](bench/evidence/2026-11-03-async-file-sink/README.md) 候选均因控制或尾部退步撤回；V3 schema CRC 则保留生产。消费校验版通过实际producer/通用CRC/24row单copy/对象预算门槛，E-core 320项有50个qualified lead，但async Mmap P1 sampled schema p99 717→747ns且定向复测719→782ns，按预定负向门槛拒绝。16行版改为只复用原16个row、rodata增长0B，E-core 60个qualified lead、23/32 written lead，但full-run有6个latency/init负向；六轴定向复测全部inconclusive且窗口受无关100% CPU测试干扰，仍按预定门槛拒绝。V3 schema CRC把reference+padding并入payload一次折叠，E-core两窗口treatment合计81 qualified lead/0 negative，V1 control仅第一窗口2个0.14%级非复现负向；同格式V3-control A/B中treatment 27 lead/0 negative、V1路径仅layout噪声，V3 schema journal格式已保留生产并通过`verify-local` 157/157步骤、775/776测试、package-distribution 2/2、check-platforms 10/10；生产热路径与测量binary归一化指令相同。保留后双拓扑完整Foundation矩阵（各240 trials、2424万JSON）为E-core `target_not_met_in_selected_cases`（29 lead/94 peer/293 inc）、P-core `inconclusive`（2 lead/414 inc）；kron lead集中在P1 memory batch，P4/mmap与tracing仍领先，未更新完整排名。P4 mmap单trial PMU显示kron 786M instructions/485M cycles、Foundation 1.828B/904M，kron CPU更少但wall-clock更慢；扩展PMU显示kron的cache-miss/context-switch也更少，关键路径是consumer单线程decode+format+write与文件写吞吐（kron约543MB/s vs Foundation约745MB/s）。consumer spin 160项0 lead/6 negative被拒，P4差距不是sleep/wake。producer-format候选（producer格式化、consumer只写出）在E-core async 160项inline组0 lead/10 negative（0.96–0.99）被拒；kron producer已承担capture/encode/CRC/commit，迁移格式化使其成为瓶颈。mutex reserve候选（复用sync_mutex、不增Journal字段）160项0 lead、P1 5 negative、P4 11 negative被拒；std.Io.Mutex开销高于lock-free CAS。当前源码`verify_crc=false` opt-in的no-CRC诊断（E-core memory 80项）仅1 lead/10 negative，未复现旧compile-time +20%–31%；但复制源码compile-time删除slot CRC的80项诊断得到23 lead/0 negative，P1/P4 inline快约14%–17%、schema约8%。CRC仍是显著功能成本，runtime opt-in的负向更可能来自分支/代码布局；默认CRC保持，跨库比较需归一化Foundation无CRC成本。FileSink writer-thread双缓冲160项P1 2 lead/3 negative、P4 0 lead/11 negative被拒；6个E-core CPU被4 producer+consumer+writer占满，barrier成本超过I/O重叠收益。保留 `test-wire-scratch` 与 `test-crc-segments` 验证复用、嵌套预算、任意 seed、独立分段和 guard-page 边界。

等待者计数通知候选完成两核 320 项流程、3,232 万条 JSON 核对，但有稳定吞吐与尾部退步，已拒绝，见 [progress 报告](bench/evidence/2026-11-03-progress-waiters/README.md)。最新平坦 CRC 直接索引版消除了旧表重复，两核 640 项流程核对 6,464 万条 JSON，E/P 分别有 27/6 个 written 组局部领先；仍有 p99/p50 稳定反例，按门槛拒绝，见 [direct-index 报告](bench/evidence/2026-11-03-crc-flat-segments/direct-index/README.md)。生产原算法和默认协议保持，尚未全面超过两个 Foundation 前端。

可靠性证据已扩展：ext4/XFS/Btrfs/F2FS 16-run child-VM abrupt-loss、9p共享文件系统行为、真实ENOSPC/只读FS/Journal预分配拒绝、1000-seed journal/archive fuzz、并发delivery/shutdown/mmap/配置替换与1000/200次soak；sanitizer仍受Zig TSan/Helgrind工具链限制。逐项源码、正负和资格见 [当前验收状态](docs/implementation-status.md)。

应用从 **`kron.Logging`** 接入。默认 stderr、同步、text、info；单文件、多输出、轮转、Memory/Mmap 和 SPSC 使用同一套初始化、logger 获取与关闭方法。

## 快速开始

在应用构建中通过 `b.dependency("kron")` 导入模块，完整配置见 [Zig 包接入](docs/package.md)。最小程序：

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    logging.scoped("app").info("started", .{ .version = "1.0" });
    try logging.shutdown();
}
```

后台文件日志将 create 的选项设为：

```zig
.{
    .outputs = &.{.{
        .name = "file",
        .target = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
        .mode = .asynchronous,
        .format = .json,
    }},
}
```

这里的异步队列默认是有界 Memory。系统本地时间可在route选 `.timestamp=.{ .zone=.local }`，Linux显式启用libc支持；带 `At` 的源码位置使用仓库相对路径，text以无引号的 `路径:行:列` 输出。输出统一使用outputs列表；mode/queue/overflow/redaction/sampling等均逐route设置，未填写字段采用Route默认值。完整参数、context、线程、多个输出、std.log 和关闭错误处理见 [详细使用指南](docs/usage.md)。可运行源码见 [examples/](examples/README.md)。

## 模式与完成边界

| 选择 | 适合的场景 | 契约 |
| --- | --- | --- |
| sync | 小工具、单线程、较低日志频率 | 调用线程完成编码与交付 |
| shared Memory | 常规后台日志 | 有界共享队列；进程异常退出会丢失尚未交付记录 |
| shared Mmap | 需要进程崩溃恢复 | 恢复完整 commit，允许至少一次重放 |
| SPSC Memory/Mmap | 高级可选：固定线程且应用已验证收益 | 显式 attach/detach；预分配每线程队列和普通共享队列 |

`flush()` 确认 required 输出 written，`flushDurable()` 请求适用输出与 journal 的 durable 协议，`shutdown()` 关闭入场并排空。accepted、written 与 durable 的含义不同；Mmap commit 不等于断电保证。详细协议见 [异步存储](docs/async-storage.md)、[生命周期](docs/lifecycle.md) 和 [文件可靠性](docs/file-reliability.md)。

文件输出支持 portable 和 Linux io_uring 后端。网络 sink/exporter 不在当前单机范围内。

## 文档入口

| 目的 | 文档 |
| --- | --- |
| 开始使用、查参数和生命周期 | [使用指南](docs/usage.md)、[包接入](docs/package.md)、[默认接入建议](docs/default-logging.md) |
| 理解接口与内部实现 | [接口架构](docs/api-design.md)、[代码结构](docs/code-structure.md)、[整体设计](docs/design.md) |
| 修改源码、选择测试和维护证据 | [开发与验证](docs/development.md)、[测试目录](tests/README.md)、[基准目录](bench/README.md) |
| 查能力、平台和剩余工作 | [当前验收状态](docs/implementation-status.md)、[平台支持](docs/platforms.md) |
| 查全部专题与历史记录 | [文档导航](docs/README.md)、[历史记录](docs/history/README.md) |

## 构建和示例

```sh
zig build
zig build run-quick-start
zig build run-file-logging
zig build run-rolling
zig build run-local-time
zig build run-file-stdout-local-time
zig build run-mmap
zig build run-source-location
zig build run-route-policies
zig build test-logging -Doptimize=ReleaseSafe -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
```

`zig build` 安装 `kroncat` 和 `kron-bench`；依赖消费只导入库模块。`verify-local` 包括单元/集成、负向编译、真实 SIGKILL、独立包、单线程、工具与示例编译；源码分发另外运行 `test-package-distribution`。按修改范围选择的完整命令见 [开发与验证](docs/development.md)。

```sh
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
```

工具使用见 [tools/](tools/README.md)。

## 性能与发布范围

当前能力可用于固定 Zig 0.16 的 Linux 单机项目，选择 bounded Memory/portable 起步，并按应用处理过载与关闭错误。Windows、macOS、Android、iOS 有实现和交叉编译/部分链接证据，仍需实际设备运行资格；包版本为 0.1.0。

完整流程比较包括字段捕获、系统时钟、编码、实际输出、written flush、关闭和清理。最近一次完整同轮跨库对照使用fd4e941的Logging基线，与Foundation真实spdlog/Rust tracing前端完成200项试验、2020万条输出核对：JSON中位吞吐对spdlog组合多数领先，与tracing公共JSON组合互有胜负；原生build_tracing文本单列。全部跨库速度比仍受波动限制，SPSC的p99.9仍有差距。2026-11-02另以当前源码完成缩减同轮抽查：P-core窗口 vs Foundation + spdlog，Memory P1 batch 1.125×达到局部门限，其余组inconclusive；vs Foundation + Rust tracing，两次相同80项抽查方向不一致，首轮三个局部资格在复测中未复现，当前P-core对照保持inconclusive。无SMT兄弟的物理核（E-core）窗口则相反：tracing 8组中位全高、5组达到门限；spdlog 5组达到门限领先，Mmap P4 batch约0.580×。随后完成E-core 160项完整JSON矩阵（1616万条）：tracing在16个JSON对照中全部领先kron async/SPSC；spdlog在多数P4/Mmap组领先；kron async仅Memory P1 batch接近持平（1.002×），SPSC Memory P1 sampled略领先（1.063×），其余组落后；SPSC比async提高约5%–15%，但不足以改变Foundation领先。同一源码的P-core 160项完整矩阵（1616万条）受宿主负载影响，大多数组spread超10%、配对比较inconclusive；方向上kron async/SPSC对spdlog多数≥1，对tracing在Memory P1/Mmap P1落后、P4部分领先。禁用CRC诊断（复制源码、非生产）显示E-core Memory P1/P4吞吐提升26.3%/31.1%，量化CRC producer/consumer校验是E-core差距的主要组成。随后新增显式opt-in `MemoryQueueOptions.verify_crc=false`：仅volatile memory queue生效，默认仍为true，mmap/可恢复journal拒绝；生产build E-core P1/P4提升20.0%/23.1%。该模式只适合明确接受未检测内存损坏风险的应用。因此当前性能对CPU拓扑高度敏感，不能把任一窗口作为全面排名；需要双拓扑profile与功能归一化比较。详见 [E-core完整矩阵](bench/cpp_reference/evidence/2026-11-02-managed-frontends-ecore-full/README.md)、[P-core完整矩阵](bench/cpp_reference/evidence/2026-11-02-managed-frontends-pcore-full/README.md)、[nocrc诊断](bench/evidence/2026-11-02-nocrc-diagnostic/README.md)、[E-core tracing](bench/cpp_reference/evidence/2026-11-02-current-tracing-quiet-affinity/README.md)与 [E-core spdlog](bench/cpp_reference/evidence/2026-11-02-current-foundation-quiet-affinity/README.md)。fresh mmap初始化优化使16.8MB journal init中位54.2/53.8ms→8.2/6.9ms。精确源码、配置和详细数字见 [前端对照](bench/cpp_reference/evidence/2026-11-02-managed-frontends/detailed-comparison.md)、[spdlog抽查](bench/cpp_reference/evidence/2026-11-02-current-foundation-spotcheck/README.md)与 [tracing抽查](bench/cpp_reference/evidence/2026-11-02-current-tracing-spotcheck/README.md)。

当前数字输出优化完成140项真实文件、4214万条JSON核对，shared Memory/Mmap P1/P4完整用户态指令稳定减少3.43%–3.47%；完整吞吐/尾延迟仍未取得一般资格，未据此更新跨库排名。最新源码、验证与所有正负结果见 [数字输出证据](bench/evidence/2026-11-02-decimal-u32-chunks/README.md)。

随后 checked wire typed visitor 将已验证 scalar 直接交给按 tag 编译的 writer，跳过中间 `Value` 物化和通用二次分派；40项完整 shared 真实文件核对1204万条JSON，Memory/Mmap P1/P4 用户态指令中位减少1.65%–1.69%，完整吞吐/尾部仍未取得一般资格。源码、独立差分和全部正负结果见 [wire scalar证据](bench/evidence/2026-11-02-wire-scalar-render/README.md)。

最新一轮把 JSON 固定 metadata 的 timestamp/session/sequence/route_mask/config_generation 直接以 comptime tag 和原始 u64/i64 写出，跳过临时 `Value` union、运行时 tag 分派和 u64→u128 宽整数路径。40项完整 shared 核对1204万JSON，四组用户态指令中位减少2.45%–2.48%；80项未插桩流程核对2408万JSON，八组 written 吞吐全为正、六组达到噪声门限，P4 batch 中位区间不重叠；text/logfmt 控制组与尾部波动仍保留。源码、正负数据与复现见 [metadata证据](bench/evidence/2026-11-02-wire-metadata-direct/README.md)。

JSON severity 字段改为按 Level 枚举选择一个完整 literal 一次写出，`err` 仍保持 `"err"` 拼写。JSON encoder probe instructions 中位 −2.05%；40项完整 shared 核对1204万JSON，四组指令中位减少1.68%–1.70%。80项 workflow 吞吐正负混合，不作一般吞吐承诺。源码与全部数据见 [severity证据](bench/evidence/2026-11-02-json-severity-literal/README.md)。

同负载 A/B 对比 fd4e941 与当前源码：E-core 5 次 batch 中 current 的 Memory P1/P4、Mmap P1/P4 分别快 **14.6%/11.8%/11.4%/7.2%**；P-core 窗口噪声较大。近期优化没有造成 E-core 回退；E-core 相对 Foundation 仍落后，是 journal CRC/恢复、typed capture 与 consumer 格式化的功能成本，不是这些优化导致。数据见 [A/B证据](bench/evidence/2026-11-02-fd4e941-current-ab/README.md)。

Memory journal初始化此前在`Storage.createMemory`完整清零后又由`format.initialize`清零，并额外逐页写0；现在memory backing只保留一次完整writable清零，header/checkpoint由zeroed入口写出，该轮file/mmap仍执行完整清零。16.8MB journal的batch runtime init中位9.13ms→6.64ms（5/5配对下降），sampled 10.79ms→6.99ms（区间仍重叠）；512B小队列差异低于宿主噪声。该结果针对初始化局部成本，不代表吞吐或跨库排名，详见 [memory init证据](bench/evidence/2026-11-02-memory-init-zeroing/README.md)。

Fresh Linux mmap在ext4/XFS/btrfs/F2FS等能证明fresh extents读为零的文件系统上改为只写header/checkpoint，并依赖`MAP_POPULATE`跳过整段清零与逐页写；未知文件系统继续完整清零，Windows/Darwin保留prefault但改为只读touch。16.8MB journal的sampled/batch init中位54.2/53.8ms→8.2/6.9ms，5/5配对下降且中位区间不重叠；512B小队列差异低于噪声。ext4新文件/截断后扩展文件的16MiB探针均为0个非零字节。该结果不代表稳态吞吐、durable或非Linux设备资格，详见 [fresh mmap证据](bench/evidence/2026-11-02-mmap-fresh-zero-init/README.md)。

原始数据、失败/慢值、各轮源码身份与局部 before/after 均保留在 evidence；历次 README 性能叙述见 [历史快照](docs/history/readme-before-reorganization.md)。完整目标的剩余工作由 [当前验收状态](docs/implementation-status.md) 跟踪。
