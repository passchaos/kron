# Flush、deadline 与关闭

多线程构建的 `Runtime` 拥有 journal、后台交付线程、预分配控制槽和控制线程；传入的 sink 仍由应用拥有。应用停止所有 logger/token 用户后，先销毁 runtime，再销毁 sink。本文的后台线程消费本机 journal。

普通异步 `memory_queue` 使用同样后台交付和admission cut，但存储是调用方allocator提供的内存。`flush(.durable)`可确认支持耐久协议的输出文件；不会持久化内存队列或生成其checkpoint。程序崩溃时未交付的内存记录丢失。详见 [异步存储选择](async-storage.md)。

`single_threaded=true` 构建支持同步模式，初始化不分配控制对象、不创建线程。`flush`、`flushRoutes`、文件 durable 同步、配置 reload 和 `shutdown(.drain)` 正常工作。异步/SPSC 初始化在分配与 journal 创建之前返回 `ThreadsUnavailable`；`flushUntil`、`flushRoutesUntil`、`shutdownUntil` 返回 `TimedControlUnavailable`，不发布操作、不提前关闭 admission。`controlStatus().available=false`，其计数为零。应用在单线程模式下直接调用普通阻塞接口并负责外部时间预算。

## 完成边界

- `flush(.drain)` 等待目标事件被 后台交付线程 处理。
- `flush(.written)` 等待目标输出完整写成功，刷新用户态 writer 和在途 I/O。
- `flush(.durable)` 进一步执行 required sinks 的持久化同步及 journal checkpoint；不支持 durable 的 required route 返回 `UnsupportedDurability`。

`flushRoutes(names, boundary)` 只确认显式选中的 route。针对 subset 的 durable flush 不会把整个 journal 的水位宣告 durable。

普通 flush 建立 admission cut，纳入此前正在捕获但尚未 reserve 的调用；cut 结束后的新事件不属于该次保证。SPSC 对固定 channel 集合建立同样的 cut。实现不会用“队列暂时为空”推断完成。

## 带 deadline 的接口

```zig
const deadline = kron.Deadline.after(io, 50 * std.time.ns_per_ms);
try runtime.flushUntil(.written, deadline);
try runtime.flushRoutesUntil(&.{"file"}, .durable, deadline);
try runtime.shutdownUntil(deadline);
```

每个调用使用一个绝对 deadline，`Deadline.after` 选择 awake 单调时钟。`Deadline.fromTimestamp` 只接受 awake/boot，拒绝可能跳变的 real 墙钟。

deadline 包含等待已有控制操作、admission cut、后台交付线程 进度、sink flush 和 sync。控制槽与线程在 runtime 初始化时预分配；调用者不把栈上的请求对象借给后台。

**`Timeout` 表示调用者停止等待，不表示 I/O 被取消。** 已发布的操作在拥有的控制线程上继续。缓冲区、journal、sink 和 runtime 必须继续存活，直到该操作完成。`runtime.controlStatus()` 暴露 busy、detached、完成/超时计数和最近控制错误。

调用者可以稍后重试：新请求等待前一操作完成，其等待时间同样计入新 deadline。一个槽位确保控制资源有界。deadline 在提交前已经过期时，不启动新操作。

`shutdownUntil` 在等待前关闭所有 channel admission，再发布 后台交付线程 的全局关闭点；非过期调用即使超时，runtime 也保持关闭 admission。尚未完成的最终 sink barrier 对应状态为 `closing`；最终 barrier 成功或失败后进入 `closed`。重复 shutdown 返回锁存的关闭结果。

## 超时后的资源管理

应用不能在 Timeout 后立即释放 sink、journal 或 Runtime。`destroy()` 会等待已发布控制操作与 后台交付线程 完成；它本身是阻塞清理接口，不提供有限时间承诺。不可恢复的底层 I/O 仍可能使它等待。

禁止在日志提交、后台交付线程、控制线程或 diagnostic hook 内调用 destroy。flush/shutdown 的对应重入返回明确错误；destroy 的生命周期前置条件违反会直接失败，避免释放正在执行的对象。

## 验证

```bash
zig build test-deadline -j1
zig build test-deadline -Doptimize=ReleaseSafe -j1
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
```

外部测试使用 entered/release 事件握手阻塞实际 sink 回调，验证 timed flush/sync、shutdown closing 状态、超时前未启动、等待占用控制槽、失败重试、生产者/worker/control/hook 重入，以及初始化后的零 allocator 调用。它们验证调用者超时和资源所有权，不能被描述成硬件 I/O 一定在 deadline 内完成。
