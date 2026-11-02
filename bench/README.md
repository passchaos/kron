# 性能基准与证据导航

先读 [基准方法](../docs/benchmark-methodology.md)：区分 producer 分位数、written 完成、durable、初始化/预热/关闭/清理，以及队列与输出的存储模式。测量保存源码/二进制身份、输入、预算、完整记录核对、失败与噪声；没有足够重复性时报告 inconclusive。

## 主入口

| 目的 | 入口/说明 |
| --- | --- |
| 完整日志流程 | [main.zig](main.zig)、`zig build bench -Doptimize=ReleaseFast -- --mode=async --storage=memory --producers=4 --sink=file --backend=portable` |
| 应用计算与无 logger 基线 | [application.zig](application.zig)、[应用说明](../docs/application-benchmark.md)、[比较脚本](application_compare.py) |
| 受控重复与回归 | [regression.py](regression.py)、[回归方法](../docs/performance-regression.md) |
| 主程序输出核验 | [validate.py](validate.py) |
| C++/Foundation 完整对照 | [cpp_reference/](cpp_reference/)、[复现说明](../docs/cpp-comparison.md)、[完整流程](../docs/cpp-full-workflow.md) |
| Runtime请求的内存与线程预算 | [runtime_resources.zig](runtime_resources.zig)、`zig build bench-runtime-resources -Doptimize=ReleaseFast -- memory /tmp/existing-directory 0`；不含全部OS资源 |
| 时钟、capture、schema、filter 等局部成本 | `bench-dispatch`、`bench-capture`、`bench-snapshot`、`bench-sampling`、`bench-encoding`、`bench-regex`、`bench-time`；命令详见专题文档 |

## 主要证据

| 证据 | 范围与边界 |
| --- | --- |
| [e8bd353 Foundation 详细对照](cpp_reference/evidence/2026-11-01-e8bd353-foundation/detailed-comparison.md) | 200 项同轮完整 Memory/Mmap；真实 spdlog 前端＋Rust 后台；中位、资源、尾部与噪声 |
| [当前kron与raw spdlog缩减同轮抽查](cpp_reference/evidence/2026-11-02-current-managed-frontends/README.md) | bc908cc；60项/606万JSON，Memory P4 batch比值3.499达到重复性门限；raw spdlog非Foundation前端，不更新排名 |
| [当前kron与Foundation缩减同轮抽查](cpp_reference/evidence/2026-11-02-current-foundation-spotcheck/README.md) | bc908cc；80项/808万JSON，Memory P1 batch比值1.125达到两侧门限；其余组inconclusive，不替代200项矩阵 |
| [当前kron与Foundation + Rust tracing缩减同轮抽查](cpp_reference/evidence/2026-11-02-current-tracing-spotcheck/README.md) | 647e667；首轮80项/808万JSON出现3个局部资格，但[相同配置复测](cpp_reference/evidence/2026-11-02-current-tracing-spotcheck-2/README.md)未复现；当前P-core对照保持inconclusive |
| [E-core quiet-affinity tracing对照](cpp_reference/evidence/2026-11-02-current-tracing-quiet-affinity/README.md) | 647e667；80项/808万JSON；单线程物理核上tracing 8组中位全高，5组达到门限，暴露kron拓扑敏感性 |
| [E-core quiet-affinity Foundation+spdlog对照](cpp_reference/evidence/2026-11-02-current-foundation-quiet-affinity/README.md) | 647e667；80项/808万JSON；单线程物理核上spdlog 5组达到门限领先，P4/Mmap差距明显 |
| [当前初始化诊断](evidence/2026-11-02-current-init-profile/README.md) | ce5aae9四配置strace与8800条JSON核对；不提供重复性/跨库排名 |
| [应用影响](evidence/2026-11-01-application-impact/README.md) | 确定性业务模型、无 logger/P1/P4/P16、JSON/结果 oracle、用户态 PMU；合成负载边界 |
| [prepared measure](evidence/2026-11-01-prepared-measure/README.md) | prepared 长度复用、节点/旧 codec 差分、完整文件与 PMU；负向尾部分位保留 |
| [消费者批处理](evidence/2026-11-01-coalesced-delivery/README.md) | ready 批次合并、确认边界、文件与故障；两后端各自的 before/after |
| [io_uring 对照](evidence/2026-11-01-uring-current/README.md) | 指定源码的实际后端比较；不能更新 Foundation 排名 |
| [线程状态预算实验](evidence/2026-11-02-thread-state-budget/README.md) | 按预算分配能减少普通Runtime空间，但P1吞吐风险未排除，候选已撤回；保留资源与完整JSON对照 |
| [当前shared profile与filter实验](evidence/2026-11-02-shared-filter-cache/README.md) | 4项profile、120项PMU、80项正式完整流程；减少filter reader原子操作未证明整体收益，候选撤回 |
| [八位十进制与冷buffered输出](evidence/2026-11-02-decimal-u32-chunks/README.md) | 保留优化；140项实际文件核对4214万JSON，四组shared指令减少3.43%–3.47%；完整速度/尾部仍inconclusive |
| [checked wire typed visitor与内联scalar渲染](evidence/2026-11-02-wire-scalar-render/README.md) | 保留优化；40项完整shared核对1204万JSON，四组用户态指令中位减少1.65%–1.69%；完整速度/尾部仍inconclusive，独立差分覆盖17527次比较 |
| [JSON固定metadata直接tag写入](evidence/2026-11-02-wire-metadata-direct/README.md) | 保留优化；40项完整shared核对1204万JSON，四组指令中位减少2.45%–2.48%；80项workflow核对2408万JSON，八组吞吐全为正、六组稳定，text/logfmt控制组与尾部波动保留 |
| [wire tag与payload合并写出](evidence/2026-11-02-wire-tag-batching/README.md) | 已否决；30项encoder probe instruction中位−0.003%、区间全部重叠，未运行完整流程，生产源码已恢复 |
| [quotedAscii改用writeVecAll](evidence/2026-11-02-quoted-ascii-vec/README.md) | 已否决；30项encoder probe JSON instructions +26.7%、输出字节一致，生产源码已恢复 |
| [短ASCII quoted合并写出](evidence/2026-11-02-quoted-ascii-short-compose/README.md) | 已否决；30项encoder probe JSON/text instructions +2.7%/+2.8%，logfmt下降未复现，生产源码已恢复 |
| [JSON severity固定字面量](evidence/2026-11-02-json-severity-literal/README.md) | 保留优化；JSON probe instructions −2.05%，40项完整shared四组指令中位减少1.68%–1.70%；workflow吞吐正负混合 |
| [fd4e941与当前源码A/B](evidence/2026-11-02-fd4e941-current-ab/README.md) | E-core 5次batch：current比fd4e941快7.2%–14.6%；P-core窗口噪声大；近期优化未造成E-core回退 |
| [慢sink过载尾部诊断](evidence/2026-11-02-overload-tail/README.md) | 合成200µs慢sink、64槽；block p99约15–16ms且无丢失，drop p99亚微秒但丢936/1000，fallback p50约0.24ms；策略取舍证据 |
| [Memory journal单次清零初始化](evidence/2026-11-02-memory-init-zeroing/README.md) | 保留优化；16.8MB journal batch init 9.13→6.64ms（5/5配对下降），sampled区间仍重叠；512B小队列低于噪声 |
| [Fresh Linux mmap只写header初始化](evidence/2026-11-02-mmap-fresh-zero-init/README.md) | 保留优化；16.8MB journal init 54.2/53.8ms→8.2/6.9ms，5/5配对下降、区间不重叠；ext4 zero契约探针通过，非白名单文件系统完整清零 |

所有其他证据从 [性能专题导航](../docs/README.md#性能机制与测量) 与历史快照进入。`evidence/` 中的冻结源码和报告保留原目录、hash 和测量身份，目录整理不重写历史结果。生成 workload、缓存和可执行文件副本由 ignore 规则排除，源码分发会验证这些产物没有进入包。

`managed_outputs.zig`测量管理入口的单/双输出完整流程，区分初始化、producer提交和written关闭时间，覆盖sync/Memory/Mmap/SPSC；`managed_outputs_compare.py`按before/after轮换配对运行，核对每条实际文件JSON，报告置信区间。用法：`zig build bench-managed-outputs -Doptimize=ReleaseFast -- memory /tmp/existing-directory 20000 2`（末尾输出数默认1，可选2）。对照脚本的`--outputs=2`校验两份完整JSON与合计written，逐输出序列和配置元数据也参与oracle。多输出独立管线会增加队列、后台线程和编码成本，单输出数字不代表多输出吞吐。

Foundation的两条前端现在分别可选`foundation`（spdlog）和`foundation_tracing`（Rust Subscriber/fmt + public MakeWriter），`--kron-frontend managed`测量当前Logging入口。公共JSON比较覆盖相同五个数值字段与完整元数据；Rust原生`build_tracing`文本通过`--metadata native_tracing`单列，保留其优化writer，避免用定制JSON入口代替标准路径。
