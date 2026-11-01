# 日志时间处理

时间能力以日志的实际使用为范围：UTC与显式固定分钟偏移、可选系统本地时间、Gregorian日期转换、RFC3339/ISO8601解析输出、精确时长与同秒缓存。默认固定偏移路径仍是纯Zig；显式local模式使用操作系统的时区规则，包括其夏令时规则，不内置IANA数据库或自己的DST算法。

已有Clock、StandardClock、NativeClock和资格化TSC负责取得时间；这层负责表示、转换与输出。事件仍使用原有i64 Unix纳秒timestamp_ns，约覆盖1677-09-21到2262-04-11。绝对墙钟可回拨，日志输出保留取得的真实值；deadline、采样和轮转仍通过独立单调时钟推进。

## 参考与取舍

| 来源 | 确认的设计 | 本库采用 |
| --- | --- | --- |
| Abseil Time/CCTZ | 绝对time、civil日历与duration不同；时区转换明确 | Timestamp、Date/DateTime、Duration与UtcOffset分别表示 |
| Howard Hinnant date | 按Gregorian周期转换日期，处理负epoch与年份边界 | 400年周期的整数日历转换，以整个周期round-trip与Python oracle验证 |
| Go time | 墙钟与单调时间用途不同；序列化不携带进程内monotonic值 | 事件墙钟与deadline时钟继续分开，不把单调读数转成日期 |
| Jiff/Temporal | 日期算术与elapsed时长区别，拒绝或显式处理歧义/边界 | 月份加减显式选择reject/clamp，越界不wrap；local转换由平台规则处理 |
| spdlog / Foundation DefaultFormatter | 按秒缓存日期与直接数字输出 | route拥有日期缓存，同秒local只转换一次，跨秒与回拨重新计算 |
| Quill | 消费者渲染事件时间，缓存可读日期 | Memory/Mmap异步的local转换在消费者执行，producer只捕获Unix纳秒 |
| RFC3339 | 显式offset、有限精度、未知offset与leap秒有不同语义 | 必须携带Z/±HH:MM；-00:00未知offset拒绝；超出9位精度不静默截断 |

固定偏移的原始测量见时间evidence。local的POSIX转换依赖libc（显式启用），Windows使用原生API；没有复制上游实现，不把调研来源的范围当作本库已实现全部通用时间能力。

## 表示与安全边界

- Date覆盖1..9999年，拒绝year0、非法month/day和无效闰日。日历加月遇到月末必须选reject或clamp；加天与加月超出范围返回错误。
- Timestamp保持事件原有i64 Unix纳秒，构造与时长加法返回OutOfRange/Overflow。Duration为i128纳秒，可表示两个极值事件时间戳之差；月数不被隐式转换为固定秒数。
- UtcOffset由固定分钟构成，RFC3339允许范围为±23:59。偏移不包含DST；例如+08:00由应用显式传入480分钟，四季不变。
- 纳秒precision默认完整9位；seconds/milliseconds/microseconds是显式向下截去小数位，auto仅去除末尾零，不损失已有精度。负epoch使用floor秒与非负小数部分，例如-1ns是1969-12-31T23:59:59.999999999Z。
- 解析支持RFC3339的T/t与Z/z，拒绝缺失偏移、非法日期、末尾垃圾、超过纳秒精度及闰秒。POSIX时间戳不能区分leap second，因此second=60返回LeapSecondUnsupported；不转换成下一分钟。
- Formatter由调用者或route拥有并串行访问，kron不使用共享日期缓存。固定模式不读取系统时区；local模式同秒不调用平台转换，跨秒/回拨才转换。输出缓冲不足前不写入任何字节。

固定模式使用明确offset，初始化后不读取文件、系统时区或网络。local模式显式读取平台时区，规则可用性和环境生命周期按下面的契约处理。

## 日志接入

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .output = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
    .mode = .asynchronous,
    .format = .json,
    .timestamp = .{
        .offset = try kron.time.UtcOffset.parse("+08:00"),
        .precision = .nanoseconds,
    },
});
defer logging.destroy();
```


JSON/logfmt保留原timestamp_ns并增加可读timestamp；text将数字前缀换成RFC3339日期。binary保留原Unix纳秒事件，配置可读timestamp会在创建/替换时返回InvalidTimestampFormat。默认timestamp=null维持原输出和原恢复指纹；默认不会新增日期转换成本。

每个启用时间的路由版本拥有一个Formatter，纳入配置内存预算，初始化或配置替换时分配，交付时在原delivery锁下更新。新事件和旧pending事件各自使用所属版本的offset/precision；filter-only reload不重置该路由状态。偏移和精度属于输出身份，进入可选恢复指纹扩展，恢复时改变它们会返回RecoveryRouteMismatch；缓存内容不进入指纹。

相同format及连续相同时间配置的目标复用本条编码结果；不同偏移或精度重新编码，避免把一个route的时间字符串用于另一个route。相同配置值的缓存命中、回拨、跨日和配置变更继续使用同一安全入口。所有权与销毁由原配置View/record pin生命周期保持，失败时不提前释放旧配置。

独立格式化可使用kron.time.rfc3339.format/parse，重复格式化可使用调用者拥有的kron.time.Formatter；完整encoder也提供encodeWithTime。示例见 [readable_time.zig](../examples/readable_time.zig)。`zig build test-time -Doptimize=ReleaseSafe -j1`运行五模式、热配置、恢复和独立Python日历oracle；`zig build bench-time -Doptimize=ReleaseFast -j1`测量同秒缓存和cache miss，完整输出参与checksum，不作为日志吞吐排名。

## 系统本地时间

显式配置 `.timestamp = .{ .zone = .local }` 自动使用系统本地时间；`offset` 保持默认UTC，不与local同时指定。`timestamp=null` 仍只输出原始数字，`.timestamp=.{}` 仍采用UTC可读时间，显式固定偏移的已有配置继续有效。

```zig
const logging = try kron.Logging.create(allocator, io, .{
    .mode = .asynchronous,
    .format = .json,
    .timestamp = .{ .zone = .local },
});
defer logging.destroy();
logging.scoped("app").info("local timestamp", .{});
try logging.shutdown();
```

`zig build run-local-time -Doptimize=ReleaseSafe` 运行完整程序。Linux消费应用通过 `b.dependency("kron", .{ .target=target, .optimize=optimize, .@"system-local-time"=true })` 开启libc链接，也可在应用模块显式 `.link_libc=true`。直接编译时加 `-lc`。默认Linux包不为固定模式增加libc依赖；未链接时local初始化返回 `LocalTimeUnavailable`。Apple/Android沿用系统libc，Windows通过原生API转换。

每个route有自己的Formatter。缓存key包含事件Unix整秒和模式；同秒保留年月日时分秒与偏移，每条只更新小数部分，跨秒、回拨或模式/固定偏移变化刷新。local的系统转换直接提供日期，不再额外做一次Gregorian转换。使用事件timestamp而不是消费时的当前时间，积压和恢复记录保持原始instant。

异步Memory/Mmap的shared/SPSC与inline/schema交付都在消费者侧转换。同步模式及显式 `fallback_sync` 在调用线程交付，因此同样会在该线程格式化；local缓存不改变这一契约。两个相同格式和时间身份的route继续复用本条编码结果。

POSIX使用 `localtime_r`，按照进程启动时的 `TZ` 或系统默认时区处理；Windows使用动态时区转换API。kron不调用tzset、不修改进程环境，也不监控系统时区的实时更改。运行期间应保持TZ和系统时区配置稳定；需要改时区时重新启动进程；平台libc对系统更新的缓存行为由平台决定，不能仅重建一个Formatter来承诺重载libc规则。DST按事件时间戳使用平台规则，不把启动时的单个offset冻结为全年规则。

初始化/配置发布时捕获时区来源指纹：POSIX的TZ规则或选中时区文件内容、Android时区属性与tzdata、Windows返回的动态时区信息。该身份进入route恢复指纹；Mmap重开时改变时区来源会返回 `RecoveryRouteMismatch`，不静默重放到新表示。kron不复制操作系统完整的时区数据库，因此此来源检查不提供对运行期外部修改或Windows历史注册表规则变化的完整快照保证。

时区来源读取有界（每个文件最多4MiB，环境名称/路径有界），仅在初始化与配置发布执行。系统转换失败返回明确错误；历史存在秒级偏移的时区无法表示为RFC3339分钟offset，返回 `NonMinuteLocalOffset`，不四舍五入或伪装UTC。日志encoder保留其现有编码错误传播边界。

独立Formatter可用 `Formatter.initWithIo(io, .{ .zone=.local })`，调用者串行访问；`Formatter.init(.{ .zone=.local })` 可用于独立格式化，但Runtime统一采用带来源身份的初始化。

验证命令：

```sh
zig test src/time/root.zig -lc -O ReleaseSafe
zig build test-local-time -Doptimize=ReleaseSafe -j1
```

单元测试验证4096个同秒时间戳只触发一次平台转换，以及跨秒、回拨、模式变化和短输出缓冲。公共管线测试覆盖Memory/Mmap × shared/SPSC × inline/schema八组，每组96条；reservation gap阻止交付期间producer没有转换，排空后只转换一次且线程ID属于消费者，Runtime初始化后的allocator没有调用。Python zoneinfo在隔离TZ的进程中独立核对6个时区×5模式的372条输出，包含DST、半小时/四十五分钟偏移、回拨、未来日期、改变时区后的恢复拒绝和历史非分钟偏移。

本轮独立ReleaseFast格式化测量共70个样本，每个10万条，700万条完整字符串的cached/stateless checksum与字节数一致。local同秒的五次中位为132.167→24.372ns/条，跨秒131.438→129.840ns/条，回拨循环132.316→24.548ns/条；同秒平台转换从10万次降为1次。测量包含字符串hash、未固定CPU或独占宿主，不代表完整logger吞吐或跨库排名。全部原值与固定cache-miss负向保留在 [本地时间证据](../bench/evidence/2026-11-01-system-local-time/README.md)。

下面保留固定偏移的历史缓存测量；不将其数值当成本轮local性能或新的跨库排名。

## 验证与缓存测量

日历测试覆盖完整Gregorian 400年周期146097天；9项时间实质测试包含负epoch/极值、400年边界、月份显式clamp、RFC解析失败和4096个随机时间戳/固定偏移round-trip及解析变异。独立Python datetime oracle另外核对4166个纳秒时间戳/offset和5845个日期，星期与年内天数精确一致，不使用浮点秒转换。

五项外部集成测试覆盖text/JSON/logfmt、sync/shared/SPSC的Memory/Mmap共五模式、初始化后无runtime分配、积压旧事件时配置替换、初始化OOM全扫描、同格式不同offset多目标，以及实际journal关闭后恢复。改变offset或precision被拒绝；正确原配置恢复timestamp_ns=0并产生+08:00输出。非法offset或binary可读time在写出前报错。

40个独立formatter样本共消费400万条完整格式字符串，cached/stateless的checksum和字节数完全一致。每组5次的本机中位如下，含时间戳更新和完整输出hash；初次build运行未固定CPU affinity，只作为本机窄范围观察。

| 输入 | 无缓存ns/次 | 缓存ns/次 | 每10万次缓存date转换 |
| --- | ---: | ---: | ---: |
| 同一Unix秒 | 52.33 | 21.53 | 1 |
| 每次下一秒 | 50.81 | 51.63 | 100000 |
| 每次切换固定offset | 52.27 | 53.23 | 100000 |
| 跨秒回拨循环 | 52.15 | 22.86 | 150 |

缓存miss与无缓存成本接近，hit避免重复日历转换；秒和offset共同决定缓存，不能用wallclock单向前进作为命中前提。这些独立数字不等同生产端延迟、完整文件吞吐或跨平台收益；最终回归、原始数据和精确源码见 `bench/evidence/2026-11-01-time/`。

此前固定偏移时间模块Debug/ReleaseSafe各10/10（含1项导入fixture和9项实质测试）；整库ReleaseFast通过81/81构建步骤、498/498 Zig测试。九目标ReleaseSafe实际编译公开时间/日志路径，时间集成、文件故障、配置23/23与独立Python oracle通过。可读时间示例在Linux实际异步写出JSON文件并独立核对原始纳秒值。Windows/macOS/Android/iOS设备运行仍待验收，编译通过不替代实际运行。精确源码与命令见 [qualification.json](../bench/evidence/2026-11-01-time/qualification.json)。
