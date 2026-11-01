# 全局采样语义与性能

采样属于不可变配置版本的策略，状态由该版本的所有producer共享。它不会给每个线程单独发一份配额；共享异步与SPSC均按同一全局预算运行。

| 配置 | 决策 |
| --- | --- |
| `.none` | 全部通过 |
| `.count=N` | 全局只通过前N次采样调用，预算到零后饱和 |
| `.every=N` | 全局原子顺序中通过第1、N+1、2N+1…次，N必须非零 |
| `.token_bucket` | 固定容量、每interval连续补充一个token，使用显式单调时间 |

Runtime先做scope/level过滤，再执行采样。默认 `sample_bypass=.warn`，warn及以上绕过采样；predicate、字段捕获和I/O发生在之后，因此通过采样的调用仍可能因predicate或捕获错误没有写出。采样预算衡量进入这一步的调用，不保证等量written记录。

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .asynchronous,
    .memory_queue = .{ .capacity = 256, .max_record_bytes = 8192 },
    .sampling = .{ .every = 2 },
    .sample_bypass = .warn,
    .routes = routes,
});
```

filter-only `reloadFilter`和`setLevelChecked`保留采样状态；完整配置替换创建新sampler并从初始预算/相位开始。旧admission与accepted记录继续遵循旧配置。count/token bucket使用CAS防重复消费，不用会下溢的fetchSub近似预算。

## every=1/2的专门路径

every=1直接返回true，state保持0，不执行RMW。every=2使用原子XOR并读取旧值最低位，state始终为0或1；修改顺序就是全局交替顺序。其他N仍使用原来的有界模N CAS，相位不转换为回绕ticket。Sampler的大小/对齐和配置预算没有变化。

当前x86_64 ReleaseFast对象中every=2生成 `lock btcq`与旧bit的返回值，没有CAS重试循环。仅使用 `fetchXor(...) == 0`仍可能生成CAS循环，因此实际反汇编已归档；其他平台的编译器可能采用不同指令，不能以源码推断所有平台成本。

顺序测试验证every1状态0、every2每步相位；并发测试核对count、every1/2/3/8、bucket的精确全局数量和最终状态。Runtime测试另外验证filter更新保留every2相位、完整替换重置。它们不依据线程完成顺序推断原子顺序。

## 重复测量

`zig build bench-sampling -Doptimize=ReleaseFast -- --producers=4 --attempts=10000 --repetitions=5` 使用固定fake time，覆盖none、every1/2/3/8、count和bucket。每次预热后在全部worker停于start gate时重置sampler，测量包括唤醒与join；没有每调用时钟读数。基准只报告sampler成本，不是完整日志吞吐或p99。

修改前/最终各105个试验（1/4/16 producer×7策略×5次），全部精确接受预算通过，另保留一次105试验的中间候选。原始数据、二进制SHA256、源码hash与反汇编位于 `bench/evidence/2026-10-31-sampling/`。

every1批次时间中位数P1为118,540→38,391ns，P4为377,381→73,461ns，P16为485,637→268,572ns。每策略10,000次调用，这些数值含线程调度开销。every2的P4/P16没有稳定胜出；部分控制策略也有环境波动，按10%噪声门限报告inconclusive。当前只确认每次原子工作的减少和语义保持，不承诺全部采样负载更快。
