# 性能基准与证据导航

先读 [基准方法](../docs/benchmark-methodology.md)：区分 producer 分位数、written 完成、durable、初始化/预热/关闭/清理，以及队列与输出的存储模式。测量保存源码/二进制身份、输入、预算、完整记录核对、失败与噪声；没有足够重复性时报告 inconclusive。

## 主入口

| 目的 | 入口/说明 |
| --- | --- |
| 完整日志流程 | [main.zig](main.zig)、`zig build bench -Doptimize=ReleaseFast -- --mode=spsc --producers=4 --sink=file --backend=portable` |
| 应用计算与无 logger 基线 | [application.zig](application.zig)、[应用说明](../docs/application-benchmark.md)、[比较脚本](application_compare.py) |
| 受控重复与回归 | [regression.py](regression.py)、[回归方法](../docs/performance-regression.md) |
| 主程序输出核验 | [validate.py](validate.py) |
| C++/Foundation 完整对照 | [cpp_reference/](cpp_reference/)、[复现说明](../docs/cpp-comparison.md)、[完整流程](../docs/cpp-full-workflow.md) |
| 时钟、capture、schema、filter 等局部成本 | `bench-dispatch`、`bench-capture`、`bench-snapshot`、`bench-sampling`、`bench-encoding`、`bench-regex`、`bench-time`；命令详见专题文档 |

## 主要证据

| 证据 | 范围与边界 |
| --- | --- |
| [e8bd353 Foundation 详细对照](cpp_reference/evidence/2026-11-01-e8bd353-foundation/detailed-comparison.md) | 200 项同轮完整 Memory/Mmap；真实 spdlog 前端＋Rust 后台；中位、资源、尾部与噪声 |
| [当前初始化诊断](evidence/2026-11-02-current-init-profile/README.md) | ce5aae9四配置strace与8800条JSON核对；不提供重复性/跨库排名 |
| [应用影响](evidence/2026-11-01-application-impact/README.md) | 确定性业务模型、无 logger/P1/P4/P16、JSON/结果 oracle、用户态 PMU；合成负载边界 |
| [prepared measure](evidence/2026-11-01-prepared-measure/README.md) | prepared 长度复用、节点/旧 codec 差分、完整文件与 PMU；负向尾部分位保留 |
| [消费者批处理](evidence/2026-11-01-coalesced-delivery/README.md) | ready 批次合并、确认边界、文件与故障；两后端各自的 before/after |
| [io_uring 对照](evidence/2026-11-01-uring-current/README.md) | 指定源码的实际后端比较；不能更新 Foundation 排名 |

所有其他证据从 [性能专题导航](../docs/README.md#性能机制与测量) 与历史快照进入。`evidence/` 中的冻结源码和报告保留原目录、hash 和测量身份，目录整理不重写历史结果。生成 workload、缓存和可执行文件副本由 ignore 规则排除，源码分发会验证这些产物没有进入包。

`managed_outputs.zig`测量管理入口的单/双输出完整流程，区分初始化、producer提交和written关闭时间，覆盖sync/Memory/Mmap/SPSC；`managed_outputs_compare.py`按before/after轮换配对运行，核对每条实际文件JSON，报告置信区间。用法：`zig build bench-managed-outputs -Doptimize=ReleaseFast -- memory /tmp/existing-directory 20000 2`（末尾输出数默认1，可选2）。对照脚本的`--outputs=2`校验两份完整JSON与合计written，逐输出序列和配置元数据也参与oracle。多输出独立管线会增加队列、后台线程和编码成本，单输出数字不代表多输出吞吐。

Foundation的两条前端现在分别可选`foundation`（spdlog）和`foundation_tracing`（Rust Subscriber/fmt + public MakeWriter），`--kron-frontend managed`测量当前Logging入口。公共JSON比较覆盖相同五个数值字段与完整元数据；Rust原生`build_tracing`文本通过`--metadata native_tracing`单列，保留其优化writer，避免用定制JSON入口代替标准路径。
