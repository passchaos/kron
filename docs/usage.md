# kron 使用指南

应用从 `kron.Logging.create` 接入。一个 Logging 管理 `outputs` 列表中的全部输出，每个 route 拥有独立的模式、队列、过滤、采样、脱敏、文件资源和交付状态。`scoped` 返回向这些输出分发的 logger。默认列表是 `&.{.{}}`，即一个名为 `stderr` 的同步 text 输出，最低级别为 info。

本指南面向 Zig 0.16；依赖声明与构建配置见 [包消费](package.md)，内部职责与 tracing 的设计对应见 [接口架构](api-design.md)。

## 最小程序

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    const log = logging.scoped("app");
    log.info("started", .{ .version = "1.0" });
    _ = try log.tryLogfAt(@src(), .warn, "request {d} completed", .{@as(u32, 42)}, .{ .elapsed = kron.durationNs(1200) });
    try logging.shutdown();
}
```

`log.info/debug/warn/err/fatal/trace` 通过 diagnostics 报告错误。需要应用处理错误时使用 `tryEmit`、`tryLogf` 或带源码位置的 `tryEmitAt`、`tryLogfAt`。普通 logger 是借用值，无须 destroy。停止全部使用者之后关闭 Logging，再销毁 owner，最后清理应用 I/O 环境。

## 一个文件与多个输出

单个文件也是一个元素的列表：

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{
            .name = "file",
            .target = .{
                .file = .{
                    .path = "app.jsonl",
                    .backend = .portable,
                },
            },
            .mode = .asynchronous,
            .format = .json,
            .redaction = &.{
                .{
                    .key = "password",
                    .action = .mask,
                },
            },
        },
    },
});
defer logging.destroy();
logging.scoped("http").info("completed", .{ .status = @as(u16, 200) });
try logging.shutdown();
```

异步模式未配置 queue 时使用有界 Memory。文件默认追加，父目录需要已存在；相对路径基于 cwd，`target.file.dir` 可传已打开的目录。Logging 拥有文件与轮转文件资源，FileSink 拥有自己打开的父目录句柄。

多个输出直接增加 route；下面的文件采用 SPSC/Mmap 保留全部事件，stdout 采用共享 Memory，每两条取一条并允许满队列丢弃。二者均使用本地时间：

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .outputs = &.{
        .{
            .name = "file",
            .target = .{
                .file = .{
                    .path = "app.jsonl",
                    .backend = .portable,
                },
            },
            .mode = .spsc,
            .max_threads = 4,
            .queue = .{
                .mmap = .{
                    .path = "app.journal",
                    .capacity = 256,
                    .max_record_bytes = 8192,
                },
            },
            .overflow = .block,
            .format = .json,
            .sampling = .none,
            .timestamp = .{
                .zone = .local,
            },
            .filter = "info",
            .redaction = &.{
                .{
                    .key = "access_token",
                    .action = .mask,
                },
            },
        },
        .{
            .name = "stdout",
            .target = .stdout,
            .mode = .asynchronous,
            .queue = .{
                .memory = .{
                    .capacity = 64,
                    .max_record_bytes = 4096,
                },
            },
            .overflow = .drop_newest,
            .format = .text,
            .sampling = .{
                .every = 2,
            },
            .delivery = .best_effort,
            .timestamp = .{
                .zone = .local,
            },
            .filter = "info",
            .redaction = &.{
                .{
                    .key = "access_token",
                    .action = .mask,
                },
            },
        },
    },
});
```

模式、容量、满队列策略、过滤、采样、脱敏都属于各自 route。每次调用只构造一次 typed 字段描述和时间戳；各管线独立判断、脱敏、复制、编码及交付。一次调用可被文件接受而被 stdout 采样或丢弃。`block` 或同步慢输出仍会延长这次调用；要让低优先级输出减少对 producer 的等待，使用异步队列和 `drop_newest`。`best_effort` 控制失败传播，本身不改变等待策略。

## Route配置与默认值

`Logging.Options`只有两个字段：`outputs`（默认`&.{.{}}`）和`max_total_queue_bytes`（默认256MiB）。模式、队列、过滤与输出策略直接设置在每个`Logging.Route`上；未填写的字段采用该Route类型的默认值。

默认列表包含一个名为stderr的同步text输出，info过滤。多个输出分别配置。

| Route参数 | 默认值 | 含义 |
| --- | --- | --- |
| `mode` | `.sync` | `.sync`、`.asynchronous` 或 `.spsc` |
| `queue` | null | 同步自动 `.none`；异步自动 Memory；可显式 Memory/Mmap |
| `overflow` | `.block` | `.block`、`.drop_newest`、`.fallback_sync` |
| `format` | `.text` | `.text`、`.json`、`.logfmt`、`.binary` |
| `timestamp` | null | 可读 UTC/固定偏移/local 日期选项 |
| `filter` | `"info"` | 默认与 scope 级别阈值 |
| `min_level` | null | 附加最低级别限制 |
| `sampling` | `.none` | none/count/every/token_bucket |
| `sample_bypass` | `.warn` | 此级别及以上绕过采样，仍受过滤和条件限制 |
| `redaction` | 空规则 | 各自队列接受前的递归脱敏 |
| `predicate` | null | 基于事件字段的接受条件 |
| `delivery` | `.required` | required 失败传播；best_effort 记录失败并继续 |
| `reclaim_after` | `.written` | 队列记录在 written 或 durable 后回收 |
| `max_threads` | 4 | SPSC 最大附着线程数 |
| `max_encoded_record_bytes` | 64 KiB | 此管线完整输出记录的 scratch 上限 |
| `max_journal_bytes` | 256 MiB | 此管线全部队列的 backing 上限 |
| `consumer_batches_per_queue` | 4 | 每轮每队列消费批数，范围1..4 |
| `diagnostics` | `.{} ` | 本输出的错误 hook 与 context |

`name` 默认 `"stderr"`，`target` 默认 `.stderr`，均只在 route 中设置。多个 route 应显式命名。target 支持 `.stderr`、`.stdout`、`.writer`、`.file`、`.rolling_file`，它描述物理目标；列表同时表达单个和多个输出。

`redaction=&.{}`表示不配置规则，`sampling=.none`表示不采样，`timestamp=null`和`predicate=null`表示不启用可读时间或字段条件。queue=null根据mode自动选择：sync使用none，异步/SPSC使用Memory；显式为sync配置queue会报错。多个Mmap route须分别使用不同journal路径。

默认 Memory 参数为 capacity256、max_record_bytes8192、schema_capacity0、max_schema_bytes8192。每个 SPSC 管线还保留普通共享队列，总队列数为 `max_threads + 1`。合计队列预算不包含文件 staging、Runtime 配置 metadata、输出 scratch 或 logger context。

FileSink.Options 包含 `path`、`dir`、`buffer_bytes=64 KiB`、`backend=.portable`、`queue_depth=4`、`append=true`。Linux 可显式选择 `.linux_uring` 或 `.auto`；当前deferred consumer批量写出中portable为实测默认，见[文件可靠性](file-reliability.md)与[后端诊断](../bench/evidence/2026-11-03-io-uring-diagnostic/README.md)。本指南示例采用 portable。

创建失败会释放已获得的内存、句柄与 Runtime。非法策略和 queue 预算在打开输出前检查；合法配置后续发生 OOM/I/O 错误时，已经创建或截断的文件内容不会被恢复。

## 方法与结果

| 方法 | 用途 |
| --- | --- |
| `scoped(scope)` | 无分配地取得向全部输出分发的 logger |
| `scopedOutput(name, scope)` | 只向指定输出提交的直接 logger，适合热点循环 |
| `attachThread(scope)` | 给全部 SPSC 输出取得各自线程 channel；其他输出继续普通路径 |
| `prepared(shape)` | 为全部异步管线预注册形状；同步输出使用普通捕获 |
| `attachPreparedThread(shape)` | 附着并为相应线程 channel 注册形状 |
| `reloadFilter(spec)` / `setLevel(level)` | 顺序更新全部输出的过滤 |
| `reloadOutputFilter(name, spec)` | 更新单个输出过滤 |
| `reloadFilterFile(path)` | 顺序为输出读取并更新过滤 |
| `flush()` / `flushDurable()` | 确认全部适用输出 written/durable |
| `flushOutputs(names)` / `flushOutputsDurable(names)` | 确认指定输出；显式选中的错误会传播 |
| `flushUntil(deadline)` / `flushDurableUntil(deadline)` | 使用一个绝对截止时间确认输出 |
| `shutdown()` / `shutdownUntil(deadline)` | 先关闭全部管线入场，再顺序排空 |
| `health()` / `outputHealth(name)` | 汇总或指定输出状态 |
| `lastResults()` | 此 OS 线程最近一次分发的逐输出结果，顺序与 outputs 一致 |
| `runtime(name)` | 借用指定输出的高级 Runtime，生命周期由 Logging 管理 |
| `bindStdLog()` / `unbindStdLog()` | 绑定或解除标准日志桥接 |
| `destroy()` | 停止全部使用者后清理全部拥有资源 |

`tryEmit/tryLogf` 的结果如下：

| 结果 | 含义 |
| --- | --- |
| `.accepted` | 至少一个输出接受；仍需 flush/shutdown 确认后台完成 |
| `.filtered` | 条件/级别拒绝；或仅有 best_effort 失败且没有输出接受 |
| `.sampled` | 采样拒绝 |
| `.dropped_full` / `.dropped_oversize` | 队列满或记录过大而丢弃 |
| `.rejected_closing` | 入场已关闭，或线程 token/重入检查拒绝 |
| 错误 | 捕获或 required 输出失败；其他输出仍可能成功 |

多个输出的提交没有回滚事务。遇到 required 错误仍尝试其他已入场输出，随后返回该错误；请通过 `lastResults()` 检查部分成功，避免盲目重试导致重复。每个元素为 `.result: EmitResult` 或 `.err: anyerror`；返回的 slice 借用到同线程下一次分发，需保留时复制。全被捕获前过滤/采样时不调用 lazy provider。递归日志被拒绝，允许有界嵌套独立 Logging（最多8层，Runtime入场合计最多64）。

汇总 health 的 accepted/written 等按输出提交统计，一条事件写两处计两次；队列大小与channel合计，混合存储报告 `.mixed`。它是观察性状态，各原子值不是事务快照。异步 `.accepted` 仅表示复制并接受记录，后续 sink 失败由输出 health、diagnostics 和 flush/shutdown 报告，不能由调用时的结果预知。

## 字段与格式串

```zig
log.info("completed", .{
    .status = @as(u16, 200),
    .cached = true,
    .elapsed = kron.durationNs(1200),
});
_ = try log.tryLogf(.info, "request {d}: {s}", .{ @as(u64, 42), "done" }, .{});
```

typed 格式串在编译期验证，异步消费者执行最终格式化。普通字段支持标量、optional、字符串、bytes、显式 array/group 等；任意对象要显式选择字段，见 [字段捕获](capture.md)、[结构化值](structured-values.md) 和 [structured.zig](../examples/structured.zig)。

```zig
const fields = [_]kron.Field{
    kron.kv("password", kron.secret("never captured")),
    kron.kv("body", kron.bytes(&payload)),
    kron.kv("nested", kron.group(&nested_fields)),
};
_ = try log.tryEmit(.info, "structured", @as([]const kron.Field, &fields));
```

顶层字段最多64项；attributes和格式参数共同受8层容器、256个value节点预算约束，循环、重复group key、过深、过大记录会被拒绝。Secret 的原值不会进入捕获。redaction 的 key 精确匹配完整字段名，并递归作用于group；点号不表示嵌套路径。每个 route 的规则在值复制进该 route 队列之前执行，不修改 caller 数据或其他输出。

自定义 `{f}` formatter 可显式采用 `tryLogfPreencoded(level, buffer, fmt, args, fields)`；应用提供字节预算，在 producer 格式化。普通 typed deferred 不借用 formatter 给后台。

函数实参在调用前求值。高成本字段用 `enabled()` guard 或 lazy provider，将工作放在 `fields()` 内：

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

`enabled()` 检查过滤，不消耗采样配额，不保证下一次提交被接受。

## Context、过滤和线程

```zig
const service = logging.scoped("http").withBorrowed(.{ .service = "api" });
const request = service.withBorrowed(.{ .request_id = "req-42", .status = @as(u16, 0) });
request.info("completed", .{ .status = @as(u16, 200) });
```

字段合并顺序为 parent < child < event。withBorrowed 不分配，slice/容器依赖存储须覆盖 child 的全部使用；普通 scope 也是借用字节。withOwned 在创建时深拷贝整个合并context，emit不再分配，应用等所有衍生值使用结束后 destroy context 一次。

```zig
var owned = try log.withOwned(allocator, .{ .user = @as([]const u8, &name) });
defer owned.destroy();
```

异步接受成功之前已经复制消息和动态值，本次调用返回后可以覆写 event 源buffer。borrowed writer 对象、缓冲及 diagnostics.context 必须存活至 Logging.destroy 返回。

```zig
try logging.reloadFilter("info,http=debug,db.query=trace,noisy=off");
try logging.reloadOutputFilter("stdout", "warn");
try logging.setLevel(.warn);
```

scope 规则覆盖默认阈值，子scope采用最具体匹配；setLevel仅改变默认值，保留scope覆盖，全量关闭使用reloadFilter("off")。采样配额在每个route的全部producer间共享，filter-only更新不重置配额。全输出更新是顺序操作，非法filter先验证；并发关闭或I/O错误仍可能留下部分更新，跨输出不承诺原子发布。单Runtime的高级配置事务见 [配置文档](configuration.md)。

环境变量由应用显式采用：`kron.environment.merge(.{ .environment = kron.environment.fromMap(init.environ_map) })` 的 filter_spec 可放入各route.filter；日志调用不读取环境或配置文件。

常规多producer使用scoped走共享队列，不需要附着线程。SPSC是固定OS线程的高级选项，仅在应用确认收益后使用：

```zig
const log = try logging.attachThread("worker");
_ = try log.tryEmit(.info, "ready", .{});
try log.detach();
```

scope 在附着时复制，全部SPSC输出各取得一个channel。任一输出的channel预算耗尽会回滚此次附着；可附着线程数受最小SPSC预算约束。handle只能在所属OS线程使用，detach使其所有复制品和衍生handle失效；旧handle不会取得新attachment。channel在初始化时预分配，detach后仍保留供消费者排空。

普通scoped可供多producer使用，在SPSC管线仍走普通共享队列。可迁移线程的任务使用普通logger。每channel保证producer顺序，多个channel与独立输出不保证同一全局顺序。关闭前先停止producer并join/detach；详见 [threaded.zig](../examples/threaded.zig)。

## Memory、Mmap与完成边界

Memory适合常规后台输出，进程异常退出会丢失尚未交付的记录。Mmap明确配置path，日志接受到文件映射队列，重开时自动校验并恢复完整pending记录。每个Mmap route必须输出到file或rolling_file，包括best_effort route；stdout/writer应选Memory或sync。高级自定义恢复sink使用Runtime。

完整混合例子见 [mmap.zig](../examples/mmap.zig)：Mmap文件和Memory stdout均输出本地时间，file为required，stdout为best_effort。相同journal/layout/目标/时间身份下重开自动恢复；健康关闭后只追加新事件。

| 边界 | Memory | Mmap |
| --- | --- | --- |
| accepted | 已复制并提交进程内队列 | 已复制并commit映射队列，不等于断电保证 |
| written | 排空先前记录并完成sink写入屏障 | 再推进适用回收/checkpoint |
| durable | 同步支持的输出文件，队列仍非持久化 | 同步适用文件和journal/checkpoint |

默认reclaim_after=written；durable回收要求Mmap，并增加同步成本。全局flushDurable跳过best_effort输出；其余required输出不支持durable时返回UnsupportedDurability。显式flushOutputsDurable选中的best_effort输出也必须满足要求。

Mmap恢复允许至少一次重复，例如文件已经写出而队列尚未确认时崩溃。各管线有自己的session/channel/sequence与配置版本，可用于各输出内去重；关联同一逻辑事件请添加应用event_id。同一事件的timestamp_ns和source一致，不承诺各输出身份相同。

SPSC文件名包括普通journal和 `app.journal.thread-0.journal` 等channel文件，均计入预算。诊断工具：`zig-out/bin/kroncat --json --recover app.journal`；只读导出不替代Runtime目标身份校验。跨代恢复与lease见 [配置文档](configuration.md)。

## Prepared与std.log

异步prepared需要每个异步route配置schema_capacity>0，schema计入queue预算。同步route使用普通捕获。注册为冷路径，bindings由Logging拥有至destroy。

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
_ = try log.tryLogf(.info, "request {d} completed", .{@as(u64, 42)}, .{ .status = @as(u16, 201) });
```

附着版本采用attachPreparedThread并detach。shape绑定消息模板、字段顺序和kind，改变返回SchemaMismatch；optional完整kind选择使用高级metadata接口，见 [schema](schema.md) 和 [prepared.zig](../examples/prepared.zig)。prepared的收益按工作负载测量，不保证所有事件更快。

标准日志桥接配置在应用根模块：

```zig
const LogBridge = kron.Logging.std_log;
pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = LogBridge.logFn,
};
```

初始化之后bindStdLog，停止全部std.log用户后unbindStdLog。Logging.destroy只解除自己的绑定。桥接使用有界16KiB producer格式化缓冲；检查LogBridge.statistics()的unbound/oversize/errors。完整例子见 [std_log.zig](../examples/std_log.zig)。

## 时间、trace 与源位置

route.timestamp可设置 `.{} `（可读UTC）、固定offset/precision或 `.{ .zone = .local }`。local采用OS时区/DST规则，按事件整秒缓存；异步在消费者转换，sync/fallback_sync在调用线程转换。Linux依赖启用 `.@"system-local-time"=true` 或应用link_libc，运行期间保持TZ稳定，见 [时间处理](time.md)。

```zig
const traced = log.withTrace(.{
    .trace_id = .{1} ** 16,
    .span_id = .{2} ** 8,
    .flags = 1,
});
_ = try traced.tryLogfAt(@src(), .info, "response {d}", .{@as(u16, 200)}, .{});
```

示例ID仅作演示，应用传入有效关联ID。trace显式传播，不自动生成ID或继承异步任务；普通日志方法不自动记录source，带At方法接受调用点@src()。

JSON source保留module/file/function/line/column，scope是应用业务组件标签。text以 `source= examples/mmap.zig:行:列` 显示仓库相对路径，不加外围引号，方便IDE终端跳转。@src().file相对模块源码根；本仓库从根examples.zig导入，保留examples/前缀。入口为src/main.zig的应用使用编译期映射：

```zig
_ = try log.tryLogfAt(kron.source.fromModule("src", @src()), .info, "request {d} completed", .{request}, .{});
```

helper保留其他source字段，规范 `/`，拒绝绝对路径和越过仓库根目录的 `..`，日志调用不查文件或拼接路径。多模块分别传仓库相对源码目录。

text侧重可读性，使用 `key= value`；logfmt保留可解析的 `key=value`，按需引用转义；JSON保留结构与类型，binary用于工具链。不要用logfmt解析器解析text。完整source输出见 [source_location.zig](../examples/source_location.zig)。

## 轮转、deadline与验证

轮转文件直接配置在route.target.rolling_file。支持三种选择：

| 配置 | 触发条件 |
| --- | --- |
| `max_bytes=10*1024*1024` | 下一条完整记录会使active文件超过10MiB时轮转 |
| `rotation_interval_ns=60*std.time.ns_per_s` | 从本轮第一条记录起经过60秒，下一条非空记录前轮转 |
| 同时设置两者 | 任一条件满足即轮转，同一条记录最多触发一次 |

```zig
.{
    .name = "hourly",
    .target = .{ .rolling_file = .{
        .path = "app-hourly.jsonl",
        .rotation_interval_ns = 60 * 60 * std.time.ns_per_s,
        .retention = 24,
        .backend = .portable,
    } },
    .mode = .asynchronous,
    .format = .json,
}
```

max_bytes默认null，禁用大小条件；rotation_interval_ns默认null，禁用时间条件，两者至少设置一个。时间轮转使用单调时间间隔，创建/reopen重置计时，进程停机时间不累计，不对齐整点或午夜；没有新日志时不创建空归档。单条记录仍须满足buffer_bytes，启用大小限制时还须满足max_bytes。

归档保留active和`.1`..`.retention`，`.1`最新。目标及journal路径应各自独立；检测到重复目标或journal冲突时创建返回错误。完整 [rolling.zig](../examples/rolling.zig) 同时演示独立的大小文件、时间文件和stderr输出。


带deadline的控制使用 `kron.Deadline.after(io, std.time.ns_per_s)`。全部管线共用绝对截止时间，超时后资源仍然有效；shutdown已关闭全部入场，必须重试shutdown确认并在停止用户后destroy。单线程仅sync/普通flush/shutdown，带deadline返回TimedControlUnavailable。

默认路径保持无每事件分配，但多输出增加各自复制、编码、配置和后台线程成本。只用一个目标的热点可取scopedOutput；多个独立队列之间不能复用已经编码的record。同格式复用仍可在高级Runtime的共享管线多route中使用，需自行管理sink生命周期。

## 性能模式选择

| 场景 | 推荐模式 | 当前证据 |
| --- | --- | --- |
| 需要 recovery、CRC、三检查点、多 route、rolling 或 durable | 默认 `Logging`/`Runtime` | durable 默认路径；P4 mmap 仍落后 Foundation（0.54–0.62），P1 sampled tracing 领先 |
| P4 高吞吐，仍需 journal/CRC/recovery | `render_cache` opt-in | 安静窗口 P4 memory batch/sampled 1.63/1.58 qualified；mmap 中位 1.51–1.61 因 spread inconclusive；最新噪声窗口 2.93–3.44M 中位领先。cache 是 volatile，journal/CRC/recovery 保留，恢复时回退 deferred render |
| P1 memory 或 P4 最高吞吐，可接受无 recovery | `text_format=true` opt-in | E-core P1 memory batch 2.307M，对 Foundation/tracing 1.286/1.038 qualified；P4 中位 3.4–3.6M 领先，窗口 spread 未 qualified |
| P1 mmap 最高吞吐、单 producer、无 recovery | `MmapSpool` opt-in | P-core batch 3.74–3.85M、sampled 3.19–3.35M；E-core 2.92–3.01M/2.57–2.62M；对两个前端中位 1.05–1.83x；无 qualified peer lead，部分配对 inconclusive |
| P1 mmap 需要 journal/recovery | 默认 durable `Runtime` | 不是最快；生产 `text_format` P1 mmap 对 tracing 为 0.888 |

选择原则：先按 recovery/durable 需求决定默认路径；P4 需要保留 journal/CRC/recovery 时用 `render_cache`；只有明确接受“崩溃可能丢失尾部记录”时才用 `text_format` 或 `MmapSpool`。`text_format` 适合 P1 memory/P4 最高吞吐，`MmapSpool` 适合单 producer 的 P1 mmap 最高吞吐。

## Mmap spool fast mode

`kron.MmapSpool` 是单 producer、非 durable 的 opt-in fast mode：producer 把最终 JSON 直接渲染进 file-backed 映射，一个 writer 线程按约 1MiB 调度 `msync(MS_ASYNC)`，`shutdown` 把文件截断到已渲染字节。没有 journal、CRC、recovery、ring 或 consumer；默认 `Logging`/`Runtime` durable 路径不变。

```zig
const spool = try kron.MmapSpool.create(allocator, io, .{
    .path = "app-fast.jsonl",
    .capacity_bytes = 64 * 1024 * 1024,
    .timestamp_period = 64, // optional: reuse one capture for 64 clock calls
});
defer spool.destroy();
const log = spool.logger("app");
_ = try log.tryEmit(.info, "event", .{ .field0 = @as(u64, 1) });
try spool.flush(.written);
try spool.shutdown();
```

边界：

- 只支持一个 producer；`channel` 固定 0，`sequence` 从 1 递增。
- `flush(.written)` 只保证 dirty page 对读者可见，不是设备 durable；`flush(.durable)` 返回 `UnsupportedDurability`。进程崩溃可能留下部分尾部记录，`shutdown` 会截断到最后一条完整记录。
- `capacity_bytes` 是映射/内存预算；容量耗尽返回 `dropped_full`，单条超出剩余空间返回 `dropped_oversize`，不会发布部分记录。
- `timestamp_period>1` 会复用一次 clock capture；staleness 以 clock-call 计数而非时间为界，需要精确时间时保持 1。
- 需要 recovery、CRC、三检查点、rolling/多 route 或 durable 时使用默认 `Logging`/`Runtime`。

性能证据：P-core spool batch 3.74–3.85M、sampled 3.19–3.35M；E-core batch 2.92–3.01M、sampled 2.57–2.62M；对 Foundation/tracing 中位 1.05–1.83x，没有 qualified peer lead；部分同窗口配对因 peer spread 保持 inconclusive。见 [mmap spool A/B](../bench/evidence/2026-11-04-mmap-spool/README.md)。

可运行示例索引见 [examples](../examples/README.md)。相关验证：

```sh
zig build test-logging test-outputs test-route-policies -Doptimize=ReleaseSafe -j1
zig build run-file-stdout-local-time run-mmap run-route-policies -Doptimize=ReleaseSafe -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
zig build test-package-distribution check-platforms -Doptimize=ReleaseSafe -j1
```

新旧API迁移：`.output`改成`.outputs=&.{.{ .target=... }}`；顶层mode/queue/filter等直接移到相应route；`.output.multiple`直接改成outputs列表；捕获前redaction配置到各相关route，或用Secret明确禁止捕获原值；借用Runtime时传输出名。
