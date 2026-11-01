# 应用入口、事件采集与输出架构

应用从 `kron.Logging.create` 接入，统一提供 `outputs` 列表。一个Logging管理全部文件、轮转、标准流writer和Runtime生命周期，每个route是独立管线，可单独设置mode、queue、overflow、过滤、采样、脱敏、格式与确认边界。默认一个stderr/sync/text/info输出；增加目标直接增加列表元素。

## 与 tracing 的对应

参考Rust tracing的职责分离、静态metadata与组合方式，保持事件采集入口独立于输出资源：

| tracing设计 | kron对应 |
| --- | --- |
| instrumentation与subscriber分离 | logger捕获typed Event，Logging管理输出管线 |
| 静态metadata与callsite interest | Zig comptime字段/格式验证、静态最低级别、版本化过滤缓存 |
| 值与静态定义分离 | 普通inline捕获；显式prepared注册scope/模板/形状 |
| layer组合过滤与输出 | outputs列表中各route独立配置策略、队列和目标 |
| span context | withTrace与borrowed/owned context；应用显式传递 |
| 应用配置一个subscriber | 一个Logging owner，一套scoped/emit/flush/shutdown |

这些对应不表示已实现tracing的全部span registry、任务instrumentation或生态layer。官方参考：[tracing](https://docs.rs/tracing/latest/tracing/)、[Layer](https://docs.rs/tracing-subscriber/latest/tracing_subscriber/layer/trait.Layer.html)、[Filter](https://docs.rs/tracing-subscriber/latest/tracing_subscriber/layer/trait.Filter.html)。

## 捕获与独立管线

组合logger先分别完成各输出的level/filter/sampling入场。没有任何输出接受入场时跳过typed字段、lazy provider与时钟。选中输出后只构造一次字段描述和时间戳，再把同一Event提交到各Runtime；Runtime在复制进自己的Memory/Mmap队列前执行有效redaction与predicate，并保留自己的配置版本、session和sequence。

异步消费者完成text/JSON/logfmt格式化，包括按事件整秒缓存的local时间。同步与fallback_sync在调用线程交付。异步接受前深拷贝动态字节，后台不借用producer栈或任意formatter。

每个Runtime独立持有采样配额、队列、worker、scratch、配置缓存、目标身份与恢复数据。Route字段自带默认值，各route分别设置sampling与redaction。需要禁止原值进入任何输出时用Secret，或确保每个相关route的有效规则覆盖该字段。

独立队列增加内存、线程、复制和编码成本。同一调用仍顺序提交各输出，block或慢同步sink会延长producer等待；best_effort不会自动改变backpressure。低优先级输出可显式异步drop_newest。

## 热路径与所有权

scoped返回值owner的泛型Frontend，避免通用动态layer链和每事件分配。单输出使用小入场帧，调用其Runtime入场/提交；多输出另外访问预分配的批量入场存储，保留至多64个入场并按反序释放，避免破坏Runtime的入场栈与版本保护。内部方法借用本次调用的owner，公共日志方法仍按值固定自己的scope/context/trace状态。最多8层独立Logging嵌套，同一Logging递归被拒绝；底层Runtime同时入场上限仍为64。

scopedOutput(name, scope)返回指定Runtime的原始logger，可用于单目标热点。attachThread在创建时预分配的attachment槽中取得各SPSC管线channel，scope复制，generation/thread校验防止跨线程使用与旧handle复活。prepared bindings在冷路径分配，由Logging拥有至destroy。

多输出分别编码，不能复用不同队列的encoded record。高级Runtime同一管线内仍可组合多个route并复用相同format/time编码，但其mode/queue和捕获保护共享；此入口用于明确需要这些取舍的应用，不增加普通接入的第二个owner。

## 结果与完成边界

一次调用不是跨输出事务：required输出失败仍尝试其他已入场输出，部分成功不会回滚；best_effort失败写入逐输出结果与diagnostics。lastResults返回当前OS线程最近一次分发的借用结果，顺序与outputs一致；异步后续I/O失败通过health和flush/shutdown报告。

health按输出提交合计，一条事件写两处计两次。全局durable只确认required输出；按名durable确认所有显式选中输出。全部控制预先检查回调重入，shutdown先关闭全部入场再顺序排空，deadline共用一个绝对时间。超时不释放仍在使用的资源。

每个Mmap管线独立校验journal路径、layout、稳定文件身份与记录版本。重启仍使用至少一次恢复，不承诺跨输出相同交付顺序或一致提交。共同事件关联用应用event_id，各输出内去重用session/channel/sequence。

## 普通入口与高级扩展

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{ .name = "file", .target = .{ .file = .{ .path = "app.jsonl" } }, .mode = .asynchronous, .format = .json },
        .{ .name = "stderr", .target = .stderr, .filter = "warn" },
    },
});
defer logging.destroy();
logging.scoped("http").info("completed", .{ .status = @as(u16, 200) });
try logging.shutdown();
```

Runtime通过 `try logging.runtime(name)` 借用，适用于跨代配置、外部sink、显式schema metadata与时钟选择。不得单独destroy这个Runtime。跨输出过滤更新是顺序操作；需要单引擎原子配置事务时采用Runtime版本接口。

详细参数、生命周期和完整示例见 [使用指南](usage.md)。性能需以完整流程实测；独立管线能力不自动带来对Foundation/spdlog的普遍优势。
