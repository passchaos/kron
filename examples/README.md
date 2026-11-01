# 可运行示例

应用从 `kron.Logging` 开始。示例使用 Zig 0.16 的 `std.process.Init`，由仓库构建添加 `kron` import；运行命令为 `zig build run-NAME -Doptimize=ReleaseSafe`。完整参数与生命周期见 [使用指南](../docs/usage.md)。

| 名称 | 源码 | 演示 |
| --- | --- | --- |
| quick-start | [quick_start.zig](quick_start.zig) | 默认 stderr、typed 字段与关闭 |
| file-logging | [file_logging.zig](file_logging.zig) | 共享 Memory、JSON 文件、脱敏与 reload |
| async-memory | [async_memory.zig](async_memory.zig) | stdout 的共享 Memory |
| structured | [structured.zig](structured.zig) | borrowed/owned、array/group、secret/bytes、lazy、trace/source、日期 |
| threaded | [threaded.zig](threaded.zig) | 两个 OS 线程的 SPSC，attach/detach、join 与错误传播 |
| rolling | [rolling.zig](rolling.zig) | 统一 owner 的轮转 JSON 文件＋stderr、独立 filter、文件 durable |
| prepared | [prepared.zig](prepared.zig) | Mmap/SPSC schema、隐藏 channel 索引的 helper |
| local-time | [local_time.zig](local_time.zig) | 消费者侧系统local日期与同秒缓存 |
| file-stdout-local-time | [file_stdout_local_time.zig](file_stdout_local_time.zig) | JSON文件＋stdout text，本地时间和源码位置 |
| mmap | [mmap.zig](mmap.zig) | 共享Mmap、required文件＋best_effort stdout、local和durable |
| source-location | [source_location.zig](source_location.zig) | JSON完整module/file/function/line/column |
| std-log | [std_log.zig](std_log.zig) | 根 std_options、bind/unbind 与动态 filter |

高级接口示例用于自定义配置、时钟或底层资源：

| 名称 | 源码 | 演示 |
| --- | --- | --- |
| basic | [basic.zig](basic.zig) | Runtime 多输出、Mmap、环境 filter |
| configuration-sources | [configuration_sources.zig](configuration_sources.zig) | 完整来源事务与 JSON 策略 |
| hot-configuration | [hot_configuration.zig](hot_configuration.zig) | 更换输出与旧资源生命周期 |
| readable-time | [readable_time.zig](readable_time.zig) | 路由日期与固定偏移 |
| predicates | [predicates.zig](predicates.zig) | 接受前条件与正则 |
| tsc-clock | [tsc_clock.zig](tsc_clock.zig) | 显式资格化与原生时钟回退 |

文件例子写入 cwd，通常追加；轮转按 retention 清理最旧归档。重复运行时根据最新 session 核对计数。`verify-local` 编译全部例子，实际运行和输出检查另行执行。

示例由仓库根 `examples.zig` 选择并导入，`@src().file` 保留 `examples/` 前缀。text的 `source=examples/mmap.zig:行:列` 无外围引号；普通包模块用 `kron.source.fromModule` 在编译期映射仓库路径，见 [源码位置](../docs/usage.md#时间trace-与源位置)。
