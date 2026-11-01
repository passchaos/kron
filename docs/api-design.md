# 应用入口、事件采集与输出架构

应用只用 `kron.Logging.create` 接入：默认控制台、单文件、多文件、轮转和混合输出共享同一初始化、logger 获取与关闭方式。`Logging` 是资源 owner，`scoped/attachThread/prepared` 返回事件采集 handle；底层 Runtime 负责队列、配置版本、交付与恢复，保留作为高级扩展和已有 API 的兼容入口。

这次接口设计参考 Rust tracing 的职责划分。tracing 是结构化诊断架构的重要参考，尤其是 instrumentation 与 subscriber 分离、静态 callsite metadata、span context，以及通过 layer 组合输出和过滤。它的优雅主要体现在职责与组合方式；实际性能仍取决于 subscriber、格式化、存储、同步和负载。

## 参考与对应

| tracing 设计 | kron 的对应 |
| --- | --- |
| 事件/跨度采集与 subscriber 分离 | 轻量 logger 捕获 typed Event，内部 Runtime 消费并交付 |
| 静态 metadata 与 callsite interest | Zig comptime 字段/格式验证、静态最低级别、已有 filter 掩码与 SPSC 配置缓存 |
| 字段值与静态字段定义分离 | 普通 inline 捕获；显式 prepared/schema 注册静态 scope/模板/形状 |
| layer 组合过滤与格式输出 | Logging 在初始化时把输出配置规范化为不可变 route；每个目标独立 format/filter/predicate/delivery |
| 显式或作用域关联 span context | kron.withTrace 复制 TraceContext，withBorrowed/withOwned 组合 context；任务传播仍由应用负责 |
| 应用配置一个 subscriber，调用端保持简单 | 一个 Logging owner，同一套 scoped、emit、flush 和 shutdown |

以上是设计映射，不表示 kron 已实现 tracing 的全部 span 生命周期、registry、异步 task instrumentation 或生态 layer。现有 Span/TraceContext 是明确的日志关联能力，没有隐式任务继承或自动 ID 生成。

官方参考：[tracing 概念与 Subscriber](https://docs.rs/tracing/latest/tracing/)、[Layer](https://docs.rs/tracing-subscriber/latest/tracing_subscriber/layer/trait.Layer.html)、[Filter 的 callsite interest](https://docs.rs/tracing-subscriber/latest/tracing_subscriber/layer/trait.Filter.html)。其中静态 interest 缓存适用于始终/从不感兴趣的 callsite；动态 reload 的规则不能永久缓存，需要按版本失效。

## 性能与生命周期约束

Logging 只在冷路径管理输出资源，不参与每条日志的动态转发。它返回的 logger 与既有 Runtime logger 是相同类型，持有同一 Runtime/线程 token/prepared binding；emit 不再经过 Logging 虚拟调用，也不为每条事件构造通用 layer 链。

typed 字段和格式串在 producer 上捕获，异步消费者负责最终 text/JSON/logfmt 格式化。禁用级别在捕获前决定，昂贵字段通过 lazy provider 在入场后构造。输出组合在初始化时校验并发布，既有 route 掩码和不可变配置协议继续处理事件决策。显式系统local时间在消费者按事件秒缓存，producer继续捕获Unix纳秒；同步/fallback_sync保留调用线程交付。

tracing Event 的借用值只覆盖通知调用。异步 logger 必须拥有自己的快照：kron 在 accepted 返回前复制消息、字符串、bytes 和嵌套描述符；不会把栈上的 event 或任意 formatter 借给后台。动态配置继续保留旧记录的目标身份与 lease，Mmap 恢复继续校验稳定 identity。

多输出包含实际工作量：匹配、编码、写出与 required barrier。相同格式/时间设置可复用记录编码；不同设置需要对应编码。新增管理入口没有消除这些成本，也没有产生新的跨库性能排名。普通共享队列、SPSC、Memory/Mmap 与 prepared 的取舍仍需按完整流程测量。

所有 writer 对象及缓冲都位于稳定的初始化存储。文件/轮转输出由 Logging 清理，borrowed writer 由调用者管理；先停止全部 handle 用户，再关闭和销毁 owner。两个独立文件输出不能维护同一目标的独立偏移，因此重复目标会被拒绝。

## API 的层次

常规指南只要求认识 Logging 和 logger：

```zig
const logging = try kron.Logging.create(allocator, io, options);
defer logging.destroy();
const log = logging.scoped("http");
log.info("completed", .{ .status = @as(u16, 200) });
try logging.shutdown();
```

多输出通过 `options.output.multiple` 表达，轮转通过 `.rolling_file` 表达。std.log 使用 `kron.Logging.std_log` 与 `bindStdLog/unbindStdLog`；deadline 和按输出名 flush 也由 Logging 直接提供。

`logging.runtime()` 是借用的高级扩展，用于外部 custom sink、跨代恢复、复杂策略事务或静态时钟选择。调用者不得单独销毁这个 Runtime。根模块原 Runtime API 保留兼容性，README 与使用指南不把它作为常规接入必须选择的第二个 owner。

具体参数、完整程序、错误与恢复语义见 [使用指南](usage.md)。
