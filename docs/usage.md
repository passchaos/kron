# kron 使用指南（Zig 0.16）

应用从 `kron.Logging` 开始：它拥有全部配置的输出和一个底层 Runtime，统一处理初始化、稳定 writer 缓冲和销毁顺序。默认是 stderr、同步、普通文本、info 级别。后台文件日志显式选择共享异步 Memory；需要进程崩溃恢复时选择 Mmap。多输出和轮转也使用同一入口；底层 `Runtime` 保留作高级扩展。接口的职责划分参考 tracing，具体映射与性能边界见 [接口架构](api-design.md)。

本指南中的完整程序对应 `examples/` 下的可运行源码。包依赖、目标和单线程构建的完整配置见 [Zig 包接入](package.md)；平台实际验证范围见 [平台支持](platforms.md)。

## 目录

- [包接入与最小程序](#包接入与最小程序)
- [后台文件日志](#后台文件日志)
- [接口与默认配置](#接口与默认配置)
- [消息、字段与返回结果](#消息字段与返回结果)
- [Context 与存储生命周期](#context-与存储生命周期)
- [过滤、采样和字段条件](#过滤采样和字段条件)
- [多线程与 SPSC](#多线程与-spsc)
- [Mmap 恢复与持久化](#mmap-恢复与持久化)
- [预注册事件形状](#预注册事件形状)
- [接管 std.log](#接管-stdlog)
- [时间、trace 与源位置](#时间trace-与源位置)
- [轮转、多输出与热配置](#轮转多输出与热配置)
- [关闭、deadline 与错误处理](#关闭deadline-与错误处理)
- [接入检查与可运行示例](#接入检查与可运行示例)

## 包接入与最小程序

在应用 `build.zig.zon` 的 `.dependencies` 中加入 `.kron = .{ .path = "../kron" }`，在应用 `build.zig` 创建依赖并给应用模块添加 import：

```zig
const dependency = b.dependency("kron", .{ .target = target, .optimize = optimize });
app.addImport("kron", dependency.module("kron"));
```

`app` 是应用的 `*std.Build.Module`；完整构建文件见 [package.md](package.md)。本地路径相对于消费项目。库没有额外包依赖，应用提供自己的 allocator 和 `std.Io`。

以下是完整的 `src/main.zig`，也可直接运行 `zig build run-quick-start`：

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();

    const log = logging.scoped("app");
    log.info("started", .{ .version = "1.0" });
    _ = try log.tryLogf(.warn, "request {d} completed", .{@as(u64, 42)}, .{
        .elapsed = kron.durationNs(1200),
    });

    try logging.flush();
    try logging.shutdown();
}
```

`scoped("app")` 返回一个轻量 logger 值，直接调用 Runtime。创建 scoped logger 不分配，正常日志捕获和提交不分配。`Logging` 及输出资源在初始化时取得稳定堆存储，保持控制台 writer 和缓冲地址稳定；不应复制或自行释放这个 owner。

每条文本包含时间、级别、scope、消息及结构化字段。默认时间是 Unix 纳秒；需要日期可配置 `timestamp`。`log.info` 的第二个参数始终是字段；没有字段时传 `.{}`。

## 后台文件日志

服务先采用共享 Memory 队列、JSON Lines 和 portable 文件后端：

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{
        .output = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
        .mode = .asynchronous,
        .format = .json,
        .redaction = &.{.{ .key = "password", .action = .mask }},
    });
    defer logging.destroy();

    const log = logging.scoped("http").withBorrowed(.{ .service = "api" });
    _ = try log.tryEmit(.info, "request completed", .{
        .status = @as(u16, 200),
        .password = "private",
    });
    try logging.reloadFilter("info,http=debug");
    log.debug("cache hit", .{ .request_id = 42 });
    try logging.flush();
    try logging.shutdown();
}
```

文件默认追加，父目录应事先存在。相对路径基于 cwd；`output.file.dir` 可传初始化时的目录，FileSink 随后拥有自己的父目录句柄。示例见 [file_logging.zig](../examples/file_logging.zig)。Memory 队列只存在于进程内，异常退出时尚未交付记录会丢失。

异步的 producer 在调用期间复制消息、字符串、bytes 和嵌套值，后台线程渲染并写出。队列为空与 required 输出已成功完成是不同状态；通过 `flush()` 或 `shutdown()` 获取完成结果。

需要修改预算时设置：

```zig
.queue = .{ .memory = .{ .capacity = 1024, .max_record_bytes = 8192 } },
.overflow = .drop_newest,
```

`capacity` 是记录槽数，`max_record_bytes` 是每槽捕获载荷预算，包含协议头、消息、字段和 metadata，不能直接当成消息字符串长度。渲染后的 text/JSON 还受 `max_encoded_record_bytes` 约束。总队列预算包含对齐、协议头和可选 schema 表；实际值看 `health().queue_reserved_bytes`。

## 接口与默认配置

单输出与多输出都调用同一个 `Logging.create(allocator, io, options)`，成功返回 `*kron.Logging`，创建失败会回收已获得的内存、文件句柄与 Runtime 资源。文件创建/截断不是文件内容事务：即使后续因 OOM 或 I/O 失败回滚资源，已创建文件可能留在磁盘。非法 filter、采样、脱敏、predicate、时间格式和队列预算在打开输出前检查。

| 接口 | 作用 |
| --- | --- |
| `scoped(scope)` | 普通共享 logger，默认静态最低级别 trace |
| `attachThread(scope)` | 当前 OS 线程的 SPSC logger，使用结束后 `detach()` |
| `prepared(shape)` | 注册共享队列的事件形状并返回 prepared logger |
| `attachPreparedThread(shape)` | 附着当前线程并注册对应队列的形状，准备失败时自动撤销附着 |
| `reloadFilter(spec)` / `reloadFilterFile(path)` | 更新完整 filter 规则，保留采样相位 |
| `setLevel(level)` | 只修改默认级别，保留 scope 覆盖，返回生命周期错误 |
| `health()` | 获取交付、丢弃、错误、队列与生命周期状态 |
| `flush()` | 确认调用覆盖范围内 required 输出完成 written |
| `flushDurable()` | 进一步确认 supported required 输出与适用 journal 的 durable 边界 |
| `flushOutputs(names)` / `flushOutputsDurable(names)` | 只确认显式命名输出的 written/durable 边界 |
| `flushUntil(deadline)` / `flushDurableUntil(deadline)` | 按明确边界等待至单调时钟 deadline |
| `bindStdLog()` / `unbindStdLog()` | 绑定/解除根 std.log 适配，owner 销毁时也解除自己的绑定 |
| `shutdown()` / `shutdownUntil(deadline)` | 关闭入场、排空并返回最终写出结果，可重复调用 |
| `destroy()` | 阻塞等待并按 Runtime → 全部拥有的输出 → owner 的顺序清理 |
| `runtime()` | 借用的高级 Runtime；生命周期由 Logging 管理 |

`Logging.Options` 的字段：

| 字段 | 默认值 | 用途 |
| --- | --- | --- |
| `output` | `.stderr` | `.stderr` / `.stdout` / `.file` / `.rolling_file` / `.writer` / `.multiple`（见多输出章节） |
| `mode` | `.sync` | `.sync` / `.asynchronous`（共享）/ `.spsc`（附着线程） |
| `queue` | `null` | async/SPSC 自动采用 Memory；sync 必须保持 null；可显式选 `.memory` 或 `.mmap` |
| `format` | `.text` | `.text` / `.json` / `.logfmt` / `.binary` |
| `timestamp` | `null` | 可读 RFC3339：UTC/固定偏移或 `.zone=.local`，binary 不支持 |
| `filter` | `"info"` | 默认阈值与 scope 覆盖 |
| `overflow` | `.block` | 满队列时 block / drop_newest / fallback_sync |
| `max_threads` | `4` | SPSC 预分配 channel 数，支持 1..64；共享模式不创建这些 channel |
| `max_journal_bytes` | `256 MiB` | 所有 Memory/Mmap 队列的总存储预算 |
| `max_encoded_record_bytes` | `64 KiB` | 完整输出记录的编码 scratch 预算 |
| `consumer_batches_per_queue` | `4` | 1..4；较小值缩短其他队列等待，较大值保留更多批处理局部性 |
| `reclaim_after` | `.written` | required 输出的队列回收边界；异步 durable 回收要求 Mmap |
| `redaction` | 空规则 | key 精确匹配的递归 drop / mask 规则 |
| `sampling` | `.none` | 全局采样策略 |
| `sample_bypass` | `.warn` | warn 及以上默认绕过采样 |
| `predicate` | `null` | 接受前的字段条件 |
| `diagnostics` | `.{}` | 错误 hook 及其借用 context |

自动 Memory 配置为 `capacity=256`、`max_record_bytes=8192`、`schema_capacity=0`、`max_schema_bytes=8192`。SPSC 还保留普通共享队列，所以总队列数为 `max_threads + 1`；`scoped()` 在 SPSC 模式中仍使用共享队列。所有 channel 在创建时预分配，不能靠 detach 降低已保留空间。

文件选项沿用 `FileSink.Options`：`path` 必填，`dir=null`、`buffer_bytes=64 KiB`、`backend=.auto`、`queue_depth=4`、`append=true`。指南显式选 portable；Linux 可选 `.linux_uring`，其写出与 durable 完成契约见 [文件可靠性](file-reliability.md)。auto 的后端选择不应被当成某次基准已经使用 io_uring 的证明。

`text` 将时间和级别直接放在行首，侧重阅读；`logfmt` 将所有内容统一为 `key=value`，并用 `attr.` 区分业务字段与元数据。下面省略session、sequence等公共字段：

```text
text:   2026-11-01T23:00:00+08:00 info scope="http" message="completed" "status"=200
logfmt: timestamp_ns=1793545200000000000 timestamp="2026-11-01T23:00:00+08:00" severity=info scope="http" message="completed" attr.status=200
```

logfmt保留原始timestamp_ns并额外提供route/config/trace等元数据，其嵌套array/group是一个带引号的值；需要对象、数组及类型信息的结构化采集优先选JSON。文件＋stdout本地时间示例见 [file_stdout_local_time.zig](../examples/file_stdout_local_time.zig)，采用文件JSON与stdout text。

## 消息、字段与返回结果

`info/debug/warn/err/fatal/trace` 和 `log(level, message, fields)` 接收字面或动态消息。`logf/tryLogf` 另接收格式串与参数：

```zig
log.info("cache hit", .{ .key = "user:42", .size = @as(u64, 512) });
log.err("request failed", .{ .reason = error.ConnectionReset });
_ = try log.tryLogf(.info, "request {d} returned {d}", .{
    @as(u64, 42), @as(u16, 200),
}, .{ .elapsed = kron.durationNs(1200) });
```

异步 `tryLogf` 捕获 typed 参数，由后台格式化。支持 `{}`、`{any}`、`{d}`、`{x}`、`{X}`、`{b}`、`{o}`、`{s}`、`{t}`、`{e}`、`{E}`、escaped braces、命名/位置参数和有界 width/precision。格式串在编译期验证；它不是任意 std.fmt 自定义对象的隐式调用入口。需要自定义 `{f}` 时使用调用方缓冲：

```zig
var message_buffer: [2048]u8 = undefined;
_ = try log.tryLogfPreencoded(.info, &message_buffer, "custom {f}", .{custom_value}, .{});
```

此片段的 `custom_value` 由应用提供，实现 Zig 0.16 的 formatter。它在 producer 上格式化；缓冲不足返回错误。typed deferred 路径的行为见 [字段捕获](capture.md) 和 [整体设计](design.md)。

字段优先用命名 struct。动态 key 或已有 Field 列表使用 `&.{kron.kv("key", value)}`。常见类型：

| 输入 | 捕获表示 |
| --- | --- |
| bool、有符号/无符号整数（最多 128 位）、float（最多 64 位） | 对应标量 |
| string slice / byte-array pointer | 字符串，存储至少存活至本次调用返回 |
| enum / error | 名称字符串 |
| optional | null 或其支持的载荷类型 |
| `kron.bytes(slice)` | bytes；JSON 中为明确的 hex 表示 |
| `kron.durationNs(n)` / `kron.timestampNs(n)` | 带语义的时间值 |
| `kron.secret(value)` | 固定脱敏标记，原值不进入捕获记录 |
| `kron.array(values)` / `kron.group(fields)` | 显式容器 |

不自动遍历任意对象指针或对象图。命名对象需用 `Adapter(T, selected_members)`，详见 [嵌套字段与对象适配](structured-values.md)。按值 byte array 需改成有明确存储生命周期的 slice/pointer。

显式嵌套结构：

```zig
const details = [_]kron.Field{
    kron.kv("status", @as(u16, 200)),
    kron.kv("password", kron.secret("never captured")),
};
const items = [_]kron.Value{
    kron.fields.fromAny("first"),
    kron.fields.fromAny(kron.group(&details)),
};
_ = try log.tryEmit(.info, "batch completed", .{ .results = kron.array(&items) });
```

顶层合并字段最多 64 项；attributes 与格式参数共享 8 层容器、256 个 value 节点的预算。容器循环、重复 group key、超深和过大记录会被拒绝。

`tryEmit/tryLogf` 返回 `!kron.EmitResult`：

| 结果 | 含义 |
| --- | --- |
| `.accepted` | 本次提交成功；需要输出完成时仍调用 flush/shutdown |
| `.filtered` | level/scope/字段条件拒绝，没有接受记录 |
| `.sampled` | 采样拒绝 |
| `.dropped_full` | 满队列丢弃 |
| `.dropped_oversize` | 记录超限丢弃 |
| `.rejected_closing` | Runtime 已关闭入场 |
| 错误 | 捕获、提交或 I/O 失败，由调用者处理 |

`_ = try ...` 传播错误但忽略上述非错误结果。需要判断是否接受时显式匹配 `.accepted`。普通 void 日志方法通过 diagnostics 报告错误；它们的返回值不能用于确认交付。

## Context 与存储生命周期

同一个 service/request 的字段可以绑定到 child logger。合并顺序为 parent → child → event，后者覆盖同名字段：

```zig
const service_log = logging.scoped("http").withBorrowed(.{ .service = "api" });
const request_log = service_log.withBorrowed(.{ .request_id = "req-42", .status = @as(u16, 0) });
request_log.info("completed", .{ .status = @as(u16, 200) });
```

`withBorrowed` 不分配。logger 保存的 scalar 是值，slice、指针和容器依赖的存储必须覆盖这个 child logger 的全部使用；event 参数只需覆盖该次调用。普通 `scoped(scope)` 借用 scope 字节，推荐静态字符串。附着线程的 scope 被复制到 channel。

需要将 context 保存到较长生命周期对象时使用 `withOwned`：

```zig
var name = "alice".*;
var log = try logging.scoped("session").withOwned(allocator, .{
    .user = @as([]const u8, &name),
});
defer log.destroy();
@memset(&name, 'x');
log.info("still records alice", .{});
```

`withOwned` 在创建时深拷贝整个合并 context（包括 borrowed parent），正常 emit 不再分配。销毁 owned context 不会销毁 Logging/Runtime。普通 borrowed logger 不需要 destroy；owned logger 的复制品及 `withTrace` 衍生值共享同一 context，等所有使用结束后只销毁原 owner 一次。

Memory/Mmap 的异步 `.accepted` 都已完成对动态值的复制。因此 event 调用返回后可以覆写源 buffer，也可以销毁本次使用的 owned context；以后再次使用 logger 所需的 context 仍须保留。完整例子见 [structured.zig](../examples/structured.zig)。

| 资源 | 应用责任 |
| --- | --- |
| `Logging` | 停止所有用户后 destroy 一次 |
| `Logging.runtime()`、普通/prepared logger | 借用 Logging 管理的 Runtime；不得单独 destroy Runtime |
| `output.file / output.rolling_file / output.multiple` | Logging 创建并销毁其中拥有的全部文件/轮转输出 |
| stderr/stdout | Logging 刷新缓冲，标准流保持由进程管理 |
| `output.writer` | writer 对象、缓冲和自定义 context 存活至 Logging.destroy 返回，由调用者清理 |
| `diagnostics.context` | 由应用管理，存活至 Logging 清理完成 |
| borrowed child 的 slice/容器 | 覆盖 logger 的全部使用 |
| owned child | 由应用 destroy context 一次 |
| attached/prepared attached logger | 所属线程 detach，全部衍生 handle 随之失效 |

## 过滤、采样和字段条件

```zig
try logging.reloadFilter("info,http=debug,db.query=trace,noisy=off");
try logging.setLevel(.warn);
```

scope 采用匹配规则的覆盖阈值；`db.query` 的规则适用于其子 scope，使用最具体的匹配。`setLevel(.warn)` 只改默认阈值，上例 `http=debug` 等覆盖仍生效；全量关闭用 `reloadFilter("off")`。reload 在配置路径解析，日志调用不解析文本或读取环境变量。已接受的事件保留接受时的交付决策。

环境变量是显式输入：

```zig
const environment = kron.environment.merge(.{
    .environment = kron.environment.fromMap(init.environ_map),
});
const logging = try kron.Logging.create(init.gpa, init.io, .{
    .filter = environment.filter_spec,
});
```

`KRON_LOG='info,http=debug' ./app` 只在应用采用此输入时生效。另一个 shell 修改变量不会更新已运行进程；应用应触发 reload。过滤文件可用 `logging.reloadFilterFile(path)`。

函数参数在进入日志方法前求值。高成本字段应使用 `if (log.enabled(.debug)) { ... }` 或 lazy provider：

```zig
const Details = struct {
    calls: *usize,
    pub fn fields(self: @This()) struct { answer: u32 } {
        self.calls.* += 1;
        return .{ .answer = 42 };
    }
};
var calls: usize = 0;
_ = try log.tryEmitLazy(.debug, "details", Details{ .calls = &calls });
```

provider 本身的构造仍在调用前发生；把昂贵工作放进 `fields()`。过滤/采样拒绝时不执行它。`enabled()` 不消费采样决策，也不保证后续调用一定被接受。

初始化策略示意：

```zig
.sampling = .{ .every = 10 },
.sample_bypass = .warn,
.predicate = "status >= 500",
.redaction = &.{.{ .key = "password", .action = .mask }},
```

采样配额在该配置版本的所有 producer 间共享，支持 `.none`、`.count`、`.every`、`.token_bucket`；默认 warn 及以上仅绕过采样，仍受 filter 和 predicate 限制。predicate 在提交接受前评估；脱敏在进入队列前完成。redaction 的 key 是完整 key 精确匹配，递归作用于 group，点号不解释成路径。详见 [采样](sampling.md)、[条件与正则](predicates.md) 和 [热配置](configuration.md)。

## 多线程与 SPSC

普通 `logging.scoped("worker")` 可以被多个 producer 使用，走共享队列；应用仍负责 child logger 借用存储的并发安全。先采用 `.mode=.asynchronous`，测到共享竞争且线程数可预算时再选择 SPSC。

SPSC 配置与 worker 内部用法：

```zig
// Logging.create 的选项：
.mode = .spsc,
.max_threads = 4,
.queue = .{ .memory = .{ .capacity = 256, .max_record_bytes = 8192 } },
```

```zig
// 每个 worker 在自己的 OS 线程中执行：
const log = try logging.attachThread("worker");
defer log.detach() catch {};
_ = try log.tryEmit(.info, "work completed", .{ .worker_id = worker_id });
```

attached logger 带线程 ID、cookie 和 generation，不能转交另一 OS 线程；可在所属线程创建带 context/trace 的 child。detach 后所有复制/衍生 handle 失效，不要再次 detach 同一 attachment。附着满额返回 `ChannelsExhausted`；默认预分配空间不会自动扩容。完整的双线程启动、join、错误传播和关闭见 [threaded.zig](../examples/threaded.zig)。

任务可能迁移线程的调度器应使用共享 logger；有明确固定线程绑定的执行器才适合附着 logger。SPSC 保证每个 channel 的 producer 顺序；多个 channel 的消费不提供跨 producer 的墙钟排序。

满队列策略对 Memory/Mmap 都适用：

| 策略 | 对业务线程的影响 |
| --- | --- |
| `.block` | 等待空间，队列饱和或慢输出会形成背压 |
| `.drop_newest` | 拒绝本条新记录，监控 dropped_full |
| `.fallback_sync` | 满时在调用线程同步交付，可能显著增加调用延迟 |

单线程应用在应用模块与 dependency 中都设置 `single_threaded=true`，使用默认 `.sync`，不传 queue。async/SPSC 创建返回 `ThreadsUnavailable`；普通同步 flush/shutdown 仍可用。完整构建见 [package.md](package.md)。

## Mmap 恢复与持久化

需要恢复进程崩溃前已提交、尚未交付的记录时配置稳定文件输出与 journal：

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .output = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
    .format = .json,
    .mode = .asynchronous,
    .queue = .{ .mmap = .{
        .path = "app.journal",
        .capacity = 256,
        .max_record_bytes = 8192,
    } },
});
```

Mmap 没有静默降级到 Memory。Logging 的 Mmap 要求每个 required 输出为 `.file` 或 `.rolling_file`，它们自动提供稳定的绝对路径恢复身份；控制台/borrowed writer 可作为 best_effort 多输出目标，作为 required 时返回 `MmapRequiresFileOutput`。高级自定义 sink 可通过 Runtime 提供显式 recovery identity。

完整例子见 [mmap.zig](../examples/mmap.zig)，运行 `zig build run-mmap -Doptimize=ReleaseSafe`。它使用共享Mmap队列，同时向 `kron-mmap.jsonl` 追加JSON、向stdout输出text，两者使用系统本地时间。文件为required，stdout为best_effort；退出前显式flushDurable和shutdown。重新运行使用同一journal/layout/输出及时区来源，初始化自动恢复尚未交付的完整记录；正常关闭后的再次运行只追加本次三条新事件。

重启使用同一 journal layout、路径和输出配置，恢复完整 committed 记录。改变容量、schema 表、输出路径/格式/可读时间等可能导致 layout 或恢复身份不匹配，初始化返回错误并保留 journal。单个 journal 有独占锁，不能让两个活动 owner 同时打开它。

SPSC 采用 `.mode=.spsc` 和相同 `.queue=.mmap`，创建共享 journal 以及 `app.journal.thread-0.journal` 等预分配 channel 文件。它们都计入预算，channel 创建与首次准备会有额外启动和磁盘成本。

| 边界 | Memory | Mmap |
| --- | --- | --- |
| accepted | 已复制进内存队列 | 已完整 commit 到映射队列 |
| 进程崩溃后未交付记录 | 丢失 | 可恢复完整 commit，允许重放 |
| written | required 输出完整写出 | 同样写出，并按回收协议推进 |
| durable | 排空此前事件并同步支持的输出文件 | 进一步包含适用 journal/checkpoint 同步 |

Mmap accepted 不等于断电保证；恢复允许至少一次重复，例如文件已写出但尚未完成队列确认时崩溃。需要去重时使用输出里的 `session/channel/sequence`，或应用自身稳定事件 ID。

默认 `.reclaim_after=.written`。若必须在输出 durable 后才回收队列，异步设置 `.reclaim_after=.durable`，必须使用 Mmap，并接受同步成本。Memory 可以 `flushDurable()` 确认此前日志的输出文件，但不能持久化进程内队列。标准流或不支持 durable 的 required sink 返回 `UnsupportedDurability`。详见 [异步存储](async-storage.md) 和 [文件可靠性](file-reliability.md)。

只读诊断工具：

```sh
zig build
zig-out/bin/kroncat --json --recover app.journal
```

只读导出不代替 Runtime 的目标身份校验与恢复交付。热路由后存在旧代 pending 记录时，使用 Runtime 的 `recovery_versions` 恢复，见 [配置文档](configuration.md)。

## 预注册事件形状

先优化通常 typed 日志，测到 metadata 捕获成本后再考虑 prepared。它需要显式 `schema_capacity > 0`，schema 表计入预算；Memory 用于进程内预注册，Mmap 保存 schema 供恢复。它不保证每个负载更快，也不会减少固定 data slot 的预留 stride。

```zig
// Logging.create 的异步/SPSC queue：
.queue = .{ .memory = .{
    .capacity = 256,
    .max_record_bytes = 4096,
    .schema_capacity = 16,
    .max_schema_bytes = 4096,
} },
```

```zig
const shape: kron.Event = .{
    .level = .info,
    .scope = "worker",
    .message = "request {d} completed",
    .message_template = true,
    .timestamp_ns = 0,
    .format_args = &.{kron.kv("0", @as(u64, 0))},
    .fields = &.{kron.kv("status", @as(u16, 200))},
};
const log = try logging.prepared(shape);
_ = try log.tryLogf(.info, "request {d} completed", .{@as(u64, 42)}, .{
    .status = @as(u16, 201),
});
```

SPSC 在所属线程把 `prepared(shape)` 换成 `attachPreparedThread(shape)`，并在使用结束后 `log.detach()`。该 helper 内部完成对应 channel 的注册，调用者不需要操作内部索引。完整 Mmap/SPSC 程序见 [prepared.zig](../examples/prepared.zig)。

shape 描述 level、scope、消息或格式串、字段名/顺序和 captured kind，示例值不保存。位置参数 key 必须是 `"0"`、`"1"` 等。改变形状返回 `SchemaMismatch`，不会自动降级；带 context 的最终字段也必须符合注册形状。

从示例值推导 optional 形状时，null 与具体值可能得到不同 kind；需要完整 optional/Value 类型掩码时，用高级 `Runtime.prewarmFormat` / `schema_site.metadata` / `prewarmMetadata`。注册是显式冷路径，Mmap schema-ready 必须经过相应同步。详见 [schema 文档](schema.md)。

## 接管 std.log

现有标准日志调用可以通过根模块 `std_options` 绑定：

```zig
const LogBridge = kron.Logging.std_log;
pub const std_options: std.Options = .{
    .logFn = LogBridge.logFn,
    .log_level = .debug,
};
```

```zig
const logging = try kron.Logging.create(init.gpa, init.io, .{});
defer logging.destroy();
{
    try logging.bindStdLog();
    defer logging.unbindStdLog();
    std.log.info("started", .{});
    try logging.reloadFilter("info,http=debug");
    std.log.scoped(.http).debug("request {d}", .{@as(u64, 42)});
}
try logging.shutdown();
```

`std_options` 要位于应用根模块。静态 `.log_level=.debug` 才能让 Runtime 在运行时控制所有标准级别；编译期被去掉的日志无法通过 reload 恢复。Bridge 在日志调用开始前绑定，停止所有 std.log 用户后 unbind，再关闭/销毁 Logging。

Bridge 使用有界 16 KiB producer 格式化缓冲；它支持标准 formatter，但不具有 typed `tryLogf` 的后台延迟格式化路径。检查 `LogBridge.statistics()` 的 unbound、oversize 和 errors 统计。完整程序见 [std_log.zig](../examples/std_log.zig)。

## 时间、trace 与源位置

可读日期通过 create 选项设置：

```zig
.timestamp = .{
    .offset = try kron.time.UtcOffset.init(480), // +08:00
    .precision = .nanoseconds,
},
```

text 使用 RFC3339 前缀，JSON/logfmt 保留 `timestamp_ns` 并增加可读时间。显式 `.timestamp = .{ .zone = .local }` 使用系统本地时区与其DST规则；默认UTC/固定偏移不查询系统时区。local同秒转换一次，异步由消费者格式化，墙钟回拨会刷新缓存。Linux包需启用 `.@"system-local-time"=true` 或在应用链接libc；运行期间保持时区环境稳定。恢复身份、平台与错误边界见 [时间处理](time.md#系统本地时间)。

trace 显式传递，不自动生成 ID，也不依赖 TLS：

```zig
const trace: kron.TraceContext = .{
    .trace_id = .{1} ** 16,
    .span_id = .{2} ** 8,
    .flags = 1,
};
const traced = log.withTrace(trace);
traced.info("linked event", .{});
_ = try traced.tryLogfAt(@src(), .info, "response {d}", .{@as(u16, 200)}, .{});
```

示例重复字节只用于演示；应用传入自己的有效 trace/span ID。带 `At` 的方法记录 source，普通方法不自动读取调用者位置。

完整源码位置例子见 [source_location.zig](../examples/source_location.zig)，运行：

```sh
zig build run-source-location -Doptimize=ReleaseSafe
```

它向 `kron-source-location.jsonl` 和stdout同时输出JSON，使用本地时间。`tryEmitAt(@src(), ...)` 演示直接消息，`tryLogfAt(@src(), ...)` 演示格式串；JSON的source包含 `module`（Zig构建模块）、`file`、`function`、`line`、`column`。`scope="http.server"` 是应用指定的业务组件名称，与 `source.module` 各有用途。把 `@src()` 放在需要定位的调用点；包装函数内部的 `@src()` 定位包装函数，想记录上层调用者时应显式传入source。

现有 [Mmap例子](../examples/mmap.zig) 和 [文件/stdout本地时间例子](../examples/file_stdout_local_time.zig) 也使用 `tryLogfAt(@src(), ...)`：文件JSON保留完整source，stdout text显示 `source="文件名":行:列`。需要在stdout也看到完整module/function等信息时选择JSON。

时钟高级选择使用借用 Runtime：`logging.runtime().loggerWithClock(kron.NativeClock, "scope")`；静态最低级别使用 `loggerWithLevel(.info, "scope")`。静态被禁用的级别无法动态打开。TSC 需显式资格检查，见 [TSC 时钟](tsc-clock.md)。

## 轮转、多输出与热配置

普通文件、轮转文件和多个目标都通过 `Logging.create` 配置。单个轮转文件使用 `.output = .{ .rolling_file = options }`；多个目标使用 `.output.multiple`，无需单独创建 sink 或 Runtime：

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .mode = .asynchronous,
    .output = .{ .multiple = &.{
        .{
            .name = "file",
            .target = .{ .rolling_file = .{
                .path = "app.jsonl",
                .max_bytes = 16 * 1024 * 1024,
                .retention = 5,
                .backend = .portable,
            } },
            .format = .json,
        },
        .{
            .name = "console",
            .target = .stderr,
            .format = .text,
            .filter = "warn",
            .delivery = .best_effort,
        },
    } },
});
defer logging.destroy();
_ = try logging.scoped("app").tryEmit(.warn, "two outputs", .{});
try logging.flushOutputsDurable(&.{"file"});
try logging.shutdown();
```

`allocator/io` 来自应用环境。完整可运行程序见 [rolling.zig](../examples/rolling.zig)。这里只需要创建和销毁一个 Logging；logger 获取、Memory/Mmap 选择、flush 与关闭同单输出一样。

每个 `Logging.Route` 配置自己的目标与输出策略：

| 字段 | 默认/语义 |
| --- | --- |
| `name` | 必填，1..64 个输出的名称必须唯一；用于显式 flush 和恢复身份 |
| `target` | 必填，stderr/stdout/file/rolling_file/borrowed writer |
| `format / timestamp / reclaim_after` | null 时继承 Logging.Options 的对应设置 |
| `filter` | null 时继承全局 filter；独立 filter 可接受全局默认级别拒绝的事件 |
| `min_level` | 可选的本目标最低级别 |
| `delivery` | 默认 required；best_effort 不提供相同交付确认 |
| `predicate` | 可选的本目标字段条件 |

每个文件目标可独立选择 portable 或 io_uring 后端；混合后端也通过同一个 owner 管理。相同配置输出可复用渲染结果，不同格式/时间策略按需重新编码，所有目标的实际 I/O 成本仍存在。

目标名称必须唯一，两个独立拥有的文件输出不能指向同一文件；重复目标返回 `DuplicateOutputTarget`，避免两个写入器维护不同偏移。单输出默认名称是 `"output"`，可用于按名称 flush。

轮转以完整记录为边界，单条记录还须小于等于 max_bytes 与 buffer_bytes，保留 active、`.1` 至 `.retention`；还可配置 `rotation_interval_ns`，在非空记录边界按单调时间检查。Logging 拥有所有文件资源，borrowed writer 的对象与存储仍由应用保留至 destroy 返回。

required 决定完成/回收保证；对文件的显式 durable flush 不宣告其他目标 durable。Mmap 允许 required 文件加 best_effort 控制台。重开时保持目标名称、身份、格式、时间设置和 journal layout 一致。

跨代热替换目标、外部 custom sink 和复杂恢复属于高级扩展，通过借用 `logging.runtime()` 或已有底层 Runtime API 操作。旧 accepted 记录继续送往旧目标，发布成功不代表可以立即销毁旧 sink；使用配置版本 readiness/collection，或显式资源 lease。Logging 继续拥有自己创建的输出；外部新资源由应用管理。

完整策略来源优先级为 defaults < file < environment < explicit，发布时深拷贝。高级生命周期步骤见 [configuration_sources.zig](../examples/configuration_sources.zig)、[hot_configuration.zig](../examples/hot_configuration.zig) 与 [配置所有权文档](configuration.md)。常规使用无需接触 Runtime。

## 关闭、deadline 与错误处理

应用关闭顺序：

1. 停止全部业务日志用户；等待 worker join，并让所属线程 detach。
2. 停止 std.log 用户并 unbind Bridge。
3. 按需要显式 `flush()` 或 `flushDurable()`，处理错误。
4. 显式 `shutdown()` 获取最终写出结果。
5. `destroy()` 清理 owner，再清理应用自有 writer、allocator 和 I/O 环境。

普通日志只要求最终排空时，`shutdown()` 已包含最终 written 收尾，可以省去独立 `flush()`。std.log 仍在 shutdown 前显式 unbind；destroy 会安全解除属于该 owner 的绑定。durable 必须显式请求；`destroy()` 的 defer 清理不提供可观察的 durable 确认。

高级有界等待：

```zig
try logging.flushUntil(kron.Deadline.after(io, 50 * std.time.ns_per_ms));
try logging.shutdownUntil(kron.Deadline.after(io, 5 * std.time.ns_per_s));
```

`Timeout` 只停止调用者等待，已发布操作可能继续执行。owner、sink 和缓冲保持存活；`destroy()` 仍会阻塞等待。单线程构建的 timed 接口返回 `TimedControlUnavailable`。禁止在提交、sink 回调或 diagnostics hook 中关闭/销毁正在执行的 Runtime。详见 [生命周期](lifecycle.md)。

`health()` 常用观察项：

| 字段 | 诊断用途 |
| --- | --- |
| `accepted / written / journal_pending` | 提交与 required 交付进度；并发读取是观察值 |
| `filtered / sampled` | 策略拒绝量 |
| `dropped_full / dropped_oversize` | 队列/尺寸不足导致的丢弃 |
| `capture_errors / write_errors / flush_errors / sync_errors` | 具体阶段失败计数 |
| `last_error / worker_alive / state` | 最近错误与生命周期 |
| `queue_storage / queue_reserved_bytes / journal_reserved_bytes` | 实际存储模式与预算 |
| `journal_high_water / recovered / thread_channels` | 压力、恢复与预分配规模 |

健康统计分别原子读取，不是跨所有字段的事务快照。需要精确核对最终计数，先停止 producer 并成功 shutdown。

常见问题：

| 现象/错误 | 检查与处理 |
| --- | --- |
| 看不到 debug | 当前 filter、scope 和静态最低级别；std.log 还检查根 std_options |
| `QueueRequiresAsyncMode` | 同步 mode 保持 queue=null |
| `ThreadsUnavailable` | 单线程构建使用 sync；应用与依赖线程设置保持一致 |
| `JournalBudgetExceeded` | 统计共享队列、全部 SPSC channel、schema 与对齐；缩小预算需求或提高总上限 |
| `ChannelsExhausted / StaleToken / WrongThread` | 附着数、detach 次数与所属线程；detach 后重新获取有效 handle |
| `SchemaMismatch` | level/scope/source、格式参数 key/kind、字段与 context 是否符合注册形状 |
| `UnsupportedDurability` | 标准流及实际平台/文件系统能力；选择支持 durable 的文件输出 |
| 文件/worker 写出失败 | 读取 last_error 与阶段计数，显式处理 shutdown 错误；保留恢复文件 |
| Mmap 重开被拒绝 | 独占锁、原 layout 与恢复身份；使用一致目标配置或只读诊断 |

文件输出的 staging buffer 也限制单条输出尺寸；增大 max_encoded_record_bytes 时按实际记录大小检查 output.file.buffer_bytes。文件部分写入失败可能留有不完整尾部，并锁存错误以阻止盲目重试；不要把重复执行同一写入当成可靠修复。需要错误回调可设置 `.diagnostics = .{ .hook = onLogError, .context = app_context }`，hook 签名为 `fn (?*anyopaque, kron.diagnostics.ErrorEvent) void`，context 存活至清理完成。

## 接入检查与可运行示例

| 示例/命令 | 覆盖能力 |
| --- | --- |
| `zig build run-quick-start` | 默认 stderr、typed 字段、格式化与关闭 |
| `zig build run-file-logging` | 共享异步 Memory、JSON 文件、脱敏与 reload |
| `zig build run-async-memory` | stdout 的共享 Memory 日志 |
| `zig build run-local-time` | 系统本地时间、消费者格式化与同秒缓存 |
| `zig build run-file-stdout-local-time` | 同时写JSON文件与stdout文本，两个输出都使用系统本地时间 |
| `zig build run-mmap` | 共享Mmap、本地时间、JSON文件＋best_effort stdout、durable与自动恢复 |
| `zig build run-source-location` | 文件/stdout JSON完整源码位置：module、file、function、line、column |
| `zig build run-structured` | owned/borrowed context、嵌套、bytes/secret、trace/source、lazy、可读日期 |
| `zig build run-threaded` | 双线程 SPSC、attach/detach、join 后关闭 |
| `zig build run-prepared` | Mmap/SPSC 预注册与 durable |
| `zig build run-std-log` | 标准日志绑定、reload 和 unbind |
| `zig build run-rolling` | 文件轮转、多 route、独立 filter 与文件 durable |
| `zig build run-basic` | 高级多输出 Mmap Runtime 与环境 filter |

文件例子写入 cwd，通常追加；反复运行会增加记录，轮转例子按 retention 删除最旧归档。生产应用给出自己的路径与保留策略。

相关验证命令：

```sh
zig test src/root.zig -O ReleaseSafe --test-filter 'managed logging'
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-package -Doptimize=ReleaseSafe -j1
zig build test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-package-distribution -Doptimize=ReleaseSafe -j1
zig build test-local-time -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
```

管理接口测试覆盖 writer 及 context 生命周期、提交后源覆写、脱敏/filter、初始化后零分配、文件/Mmap 关闭重开、预注册/附着失败清理、写出错误、非法配置前置检查和分配失败全扫描。独立包可执行文件经 `b.dependency` 使用 Logging 实际运行 sync、Memory、Mmap、SPSC-Memory、SPSC-Mmap；平台对象编译覆盖真实 managed writer/file/prepared 路径。

目标设备运行资格、进程强杀恢复和断电资格是不同证据。应用采用前按自己的负载核验输出完整性、过载策略、关闭错误和所需 durable 范围，选型依据见 [默认日志建议](default-logging.md)。
