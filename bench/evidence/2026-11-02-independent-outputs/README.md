# 独立输出管线与Route默认值验证

最终接口为 `Logging.Options{ outputs, max_total_queue_bytes }`，默认值直接在Route字段上。每个输出独立mode/queue/overflow/filter/sampling/redaction及Runtime；默认一个stderr/sync/text/info。原Output单/多union、Defaults与继承开关已删除。

组合Frontend捕获一次字段描述和事件时间，再提交到每个选中输出，反序释放入场。队列前redaction只改自己的副本；partial success通过lastResults观察，异步后续失败通过health/flush/shutdown报告。shutdown预先拒绝回调重入、关闭全部入场，然后使用同一绝对deadline排空。

轮转文件支持max_bytes（大小）、rotation_interval_ns（时间间隔）或两者任一条件。max_bytes默认null，时间条件也默认null，至少一个条件必填。纯时间轮转使用单调时间，从本轮首条记录起计时，在下一条非空记录边界触发；空闲时无空归档，不对齐整点/午夜。

## 功能证据

- `full-safe.log`：151/151步骤成功，636通过/1系统能力skip；包含九目标对象编译（复用内容缓存）、独立源码分发包、真实SIGKILL与恢复campaign、19个示例编译、字段/格式负向编译和时间oracle。平台编译不代表非Linux设备运行。
- `focused-safe.log`、`focused-fast.log`：最终源码53/53均通过；`focused-debug.log`：Logging27、独立输出15、route policy11，共53/53；包含64输出、并发采样配额、scope复制、空队列/满队列差异、队列前脱敏、capture错误、thread/prepared回滚、stale token、嵌套结果、诊断归属和shutdown超时。
- `rolling-debug.log`：22/22（含导入fixture），覆盖纯时间、大小+时间、阈值、时钟回拨/饱和、空记录、重开和无分配；`rolling-example.log`来自实际运行。
- `tests/test_managed_outputs_compare.py`：6个负向与完整输出oracle测试；管理接口基准逐条解析JSON，拒绝缺失、重复、截断、错误payload/severity。

## 单输出完整流程对照

基线为cc2cac1，`baseline-src.tar.xz`保存源码；候选由candidate.tar.xz/source-sha256.json记录。使用同一bench/managed_outputs.zig，ReleaseFast、portable文件，1producer，capacity256/max_record_bytes8192，SPSC max_threads1，warmup1000条先排空；计时包括字段/时间捕获、提交、消费者JSON编码、实际文件写出和written shutdown，初始化另外报告。每组12次，before/after轮换，固定允许CPU中的0/1。

两次独立campaign共240trial，每次20000计时事件+1000warmup，504万条实际JSON全部核对。宿主loadavg约88，未独占CPU或存储；这是本机管理入口比较，不是Foundation/spdlog排名或所有负载结论。bootstrap配对中位ratio的95%区间在原comparison.json，ratio>1表示候选更快。

| 模式 | 首轮before→after ns/事件 | 重复before→after ns/事件 | 重复吞吐变化 |
| --- | ---: | ---: | ---: |
| sync | 827.58 → 889.56 | 834.42 → 870.80 | -4.18% |
| memory | 531.98 → 571.53 | 532.65 → 574.47 | -7.28% |
| mmap | 537.79 → 603.44 | 541.04 → 577.79 | -6.36% |
| spsc_memory | 561.78 → 591.86 | 562.51 → 586.73 | -4.13% |
| spsc_mmap | 569.43 → 588.08 | 569.15 → 591.32 | -3.75% |

这次能力变更增加了统一分发状态、逐输出结果和生命周期检查。重复campaign中单输出完整流程下降约4%~7%；保留这个成本，不宣称零开销或性能提升。单目标热点可取scopedOutput(name,scope)，返回原始Runtime logger；普通scoped保留一致的多输出行为。多输出分别复制/编码/运行worker，其资源和吞吐需另测，不能由单输出结果推出。

初始化差异的区间较宽，单独报告，不与吞吐混合；Mmap fsync成本继续存在。没有改变文件布局/记录版本/CRC/schema-ready/lease协议。

## 重现

```sh
zig build test-logging test-outputs test-route-policies -Doptimize=ReleaseSafe -j1
zig build verify-local check-platforms test-package-distribution -Doptimize=ReleaseSafe -j1
zig build bench-managed-outputs -Doptimize=ReleaseFast -- memory /tmp/existing-dir 20000
python3 tests/test_managed_outputs_compare.py
```

完整指南见 [usage.md](../../../docs/usage.md)，轮转示例见 [rolling.zig](../../../examples/rolling.zig)。
