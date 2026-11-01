# 日志时间处理

时间能力补充以日志的实际使用为范围：UTC与显式固定分钟偏移、Gregorian日期转换、RFC3339/ISO8601时间戳格式化和解析、精确时长与同秒格式缓存。按用户要求，不实现夏令时、地理时区/IANA数据库或隐式系统时区查询。

已有Clock、StandardClock、NativeClock和资格化TSC负责取得时间；这层负责表示、转换与输出。事件仍使用原有i64 Unix纳秒timestamp_ns，约覆盖1677-09-21到2262-04-11。绝对墙钟可回拨，日志输出保留取得的真实值；deadline、采样和轮转仍通过独立单调时钟推进。

## 参考与取舍

| 来源 | 确认的设计 | 本库采用 |
| --- | --- | --- |
| Abseil Time/CCTZ | 绝对time、civil日历与duration不同；时区转换明确 | Timestamp、Date/DateTime、Duration与UtcOffset分别表示 |
| Howard Hinnant date | 按Gregorian周期转换日期，处理负epoch与年份边界 | 400年周期的整数日历转换，以整个周期round-trip与Python oracle验证 |
| Go time | 墙钟与单调时间用途不同；序列化不携带进程内monotonic值 | 事件墙钟与deadline时钟继续分开，不把单调读数转成日期 |
| Jiff/Temporal | 日期算术与elapsed时长区别，拒绝或显式处理歧义/边界 | 月份加减显式选择reject/clamp，越界不wrap；用户要求排除DST |
| Foundation DefaultFormatter | 同秒日期缓存、直接数字生成 | 调用者拥有的Formatter缓存以Unix秒和固定偏移为key，回拨/偏移变更重新计算 |
| RFC3339 | 显式offset、有限精度、未知offset与leap秒有不同语义 | 必须携带Z/±HH:MM；-00:00未知offset拒绝；超出9位精度不静默截断 |

参考代码与官方说明的SHA256记录在时间evidence。未增加生产依赖，没有复制上游实现，不把调研来源的范围当作本库已实现全部通用时间能力。

## 表示与安全边界

- Date覆盖1..9999年，拒绝year0、非法month/day和无效闰日。日历加月遇到月末必须选reject或clamp；加天与加月超出范围返回错误。
- Timestamp保持事件原有i64 Unix纳秒，构造与时长加法返回OutOfRange/Overflow。Duration为i128纳秒，可表示两个极值事件时间戳之差；月数不被隐式转换为固定秒数。
- UtcOffset由固定分钟构成，RFC3339允许范围为±23:59。偏移不包含DST；例如+08:00由应用显式传入480分钟，四季不变。
- 纳秒precision默认完整9位；seconds/milliseconds/microseconds是显式向下截去小数位，auto仅去除末尾零，不损失已有精度。负epoch使用floor秒与非负小数部分，例如-1ns是1969-12-31T23:59:59.999999999Z。
- 解析支持RFC3339的T/t与Z/z，拒绝缺失偏移、非法日期、末尾垃圾、超过纳秒精度及闰秒。POSIX时间戳不能区分leap second，因此second=60返回LeapSecondUnsupported；不转换成下一分钟。
- Formatter由调用者拥有并负责串行访问，不使用全局缓存、threadlocal、环境变量或allocator。缓存能处理同秒、跨日、负epoch、回拨和偏移变更；输出缓冲不足前不写入任何字节。

该模块不推断用户设备所在地。时区配置是具体可审查的offset，初始化后格式化不读取文件、系统时区或网络。五平台共享同一纯Zig日期/格式路径，平台取时能力继续按已有后端区别验证。

## 日志接入

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .routes = &.{.{
        .name = "file",
        .sink = file.sink(),
        .format = .json,
        .timestamp = .{
            .offset = try kron.time.UtcOffset.parse("+08:00"),
            .precision = .nanoseconds,
        },
    }},
});
```

JSON/logfmt保留原timestamp_ns并增加可读timestamp；text将数字前缀换成RFC3339日期。binary保留原Unix纳秒事件，配置可读timestamp会在创建/替换时返回InvalidTimestampFormat。默认timestamp=null维持原输出和原恢复指纹；默认不会新增日期转换成本。

每个启用时间的路由版本拥有一个Formatter，纳入配置内存预算，初始化或配置替换时分配，交付时在原delivery锁下更新。新事件和旧pending事件各自使用所属版本的offset/precision；filter-only reload不重置该路由状态。偏移和精度属于输出身份，进入可选恢复指纹扩展，恢复时改变它们会返回RecoveryRouteMismatch；缓存内容不进入指纹。

相同format及连续相同时间配置的目标复用本条编码结果；不同偏移或精度重新编码，避免把一个route的时间字符串用于另一个route。相同配置值的缓存命中、回拨、跨日和配置变更继续使用同一安全入口。所有权与销毁由原配置View/record pin生命周期保持，失败时不提前释放旧配置。

独立格式化可使用kron.time.rfc3339.format/parse，重复格式化可使用调用者拥有的kron.time.Formatter；完整encoder也提供encodeWithTime。示例见 [readable_time.zig](../examples/readable_time.zig)。`zig build test-time -Doptimize=ReleaseSafe -j1`运行五模式、热配置、恢复和独立Python日历oracle；`zig build bench-time -Doptimize=ReleaseFast -j1`测量同秒缓存和cache miss，完整输出参与checksum，不作为日志吞吐排名。

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

最终时间模块Debug/ReleaseSafe各10/10（含1项导入fixture和9项实质测试）；整库ReleaseFast通过81/81构建步骤、498/498 Zig测试。九目标ReleaseSafe实际编译公开时间/日志路径，时间集成、文件故障、配置23/23与独立Python oracle通过。可读时间示例在Linux实际异步写出JSON文件并独立核对原始纳秒值。Windows/macOS/Android/iOS设备运行仍待验收，编译通过不替代实际运行。精确源码与命令见 [qualification.json](../bench/evidence/2026-11-01-time/qualification.json)。
