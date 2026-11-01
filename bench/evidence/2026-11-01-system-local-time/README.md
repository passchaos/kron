# 系统本地时间与消费者按秒缓存

实现显式 `.timestamp = .{ .zone = .local }`，producer继续捕获Unix纳秒，异步消费者根据事件时间按秒调用平台local转换。固定/UTC配置保留原路径与原恢复指纹。源码和证据hash见 `qualification.json`。

## 正确性证据

- 时间模块Debug/Safe/Fast各12项通过；无libc构建11通过/1个local缓存测试按能力跳过。
- 公共管线覆盖Memory/Mmap×shared/SPSC×inline/schema八组，每组96条。reservation gap期间accepted提交触发0次转换，消费者排空触发1次，记录的转换线程不是producer；Runtime初始化后allocator不调用。
- 独立Python zoneinfo核对6个时区×5模式和同身份恢复，共372条完整时间戳；包括DST前后、半小时/四十五分钟偏移、负epoch、回拨和未来日期。
- 改变TZ后恢复返回RecoveryRouteMismatch，原journal SHA256不变；恢复原TZ后12条全部写出。1800年Paris的秒级历史偏移明确返回NonMinuteLocalOffset。
- 独立Zig包通过dependency选项启用local，多线程/单线程消费均通过。
- 九目标对象编译通过，平台能力与实际设备运行仍分别判断。

最终完整ReleaseSafe门禁109/109步骤成功，576项通过、1项local缓存测试在无libc构建中按能力跳过。local专项测试和独立oracle实际运行通过；日志保存在 `full-safe.log`，当前资格与源码hash在 `qualification.json`。

## 独立格式化测量

命令：`zig build run-local-time bench-time -Dsystem-local-time=true -Doptimize=ReleaseFast -j1`。每组五次、每次10万条，70个样本消费700万条完整格式字符串。cached/stateless逐组checksum和输出字节数完全相同。原始输出在 `formatter-example-fast.log`，结构化行在 `results.jsonl`，汇总在 `measurements.json`。

| 场景 | 非缓存中位ns/条 | 缓存中位ns/条 | 缓存每10万条日期转换 |
| --- | ---: | ---: | ---: |
| changing-second | 39.275 | 48.141 | 100000 |
| clock-rollback | 38.678 | 22.293 | 150 |
| local-changing-second | 131.438 | 129.840 | 100000 |
| local-clock-rollback | 132.316 | 24.548 | 150 |
| local-same-second | 132.167 | 24.372 | 1 |
| offset-change | 39.503 | 48.044 | 100000 |
| same-second | 54.810 | 24.714 | 1 |

local同秒从10万次平台转换降到1次；跨秒仍需转换，不会由缓存消除时区规则工作。所有场景保留原值，包括固定模式的cache-miss负向。测量包含完整字符串hash、未固定CPU或独占宿主，不能当成完整日志吞吐、稳定回归资格或跨库排名。最终example的三个真实JSON时间戳带本地+08:00，独立保留原始Unix纳秒。

## 配置与边界

Linux通过 `-Dsystem-local-time=true`（dependency选项同名）或应用链接libc显式启用；默认固定模式不新增依赖。Apple/Android使用系统libc，Windows使用原生API。kron不修改TZ或调用tzset，运行期间保持进程时区环境稳定，需要改时区时重启进程。

初始化捕获时区来源指纹，纳入Mmap恢复身份；不复制整个操作系统数据库，不提供运行中外部规则改变的完整快照保证。Windows历史注册表规则与非Linux设备运行仍需平台专项资格。同步/fallback_sync保留调用线程交付。更多使用和错误语义见 [时间文档](../../../docs/time.md#系统本地时间)。
