# 作为 Zig 项目的默认日志库

kron 已可作为固定 Zig 0.16、Linux 单机应用的默认日志实现。结构化输出、过滤与热配置、脱敏、同步/共享异步/SPSC、文件轮转、归档和进程恢复都有实际运行与错误边界门禁。应用需要明确选择队列预算、过载策略和关闭方式，并固定依赖版本；当前包版本0.1.0，不将未来API兼容性视为已经承诺。

推荐先使用 `kron.Logging`，选择普通共享异步 Memory队列、portable文件后端和text/JSON输出。它统一管理全部配置输出与底层Runtime，覆盖通常的单机应用使用方式。最小程序见 [quick_start.zig](../examples/quick_start.zig)，后台文件日志见 [file_logging.zig](../examples/file_logging.zig)，全部参数与线程/context生命周期见 [详细使用指南](usage.md)。默认 `.{}` 使用stderr同步日志，服务在各route显式设置 `.mode=.asynchronous`。

常规服务以shared Memory/Mmap为主要路径，普通scoped logger即可供多producer使用，通常不需要SPSC或thread attachment。SPSC保留为固定OS线程的高级可选能力：每线程队列会增加空间与Mmap准备成本，任务迁移受限，当前p99.9也没有一般优势；只有应用实测确认收益时才采用。Foundation的Memory与单Mmap同样是共享队列，不提供SPSC模式。

参数按应用需求配置：

| 需求 | 建议 |
| --- | --- |
| 小工具或单线程应用 | 同步模式，显式处理flush/关闭错误 |
| 后台文件日志 | 共享异步Memory，固定槽与record预算，portable后端 |
| 限制日志对应用的阻塞 | 根据业务选择drop_newest，并监控丢弃/错误；block会在满队列时等待 |
| 停止进程后仍需恢复accepted未交付事件 | Mmap journal，稳定输出身份，接受初始化/磁盘预算与至少一次重复 |
| 极高频、线程数固定且已测到共享争用 | 显式SPSC attachment，分别验证p99/p99.9和总队列保留 |
| 需要确认抵抗系统掉电 | 显式durable与实际平台/文件系统资格；written/Memory accepted不能代替它 |
| 接入现有std.log调用 | 根std_options使用`kron.Logging.std_log`，调用bindStdLog，在关闭前unbindStdLog |

应用生命周期顺序为：创建I/O和Logging、开始生产者；停止所有logger/token用户并detach、解除std.log绑定、显式flush/shutdown、销毁Logging和I/O。直接使用高级Runtime时，另外保证Runtime先于sink销毁。需要看到错误时使用`tryEmit`/flush/shutdown结果，普通void日志也应通过health/错误回调监控后台失败。std.log桥有自身的unbound/oversize/error统计，应在程序日志调用开始前绑定；它使用有界producer格式化缓冲，不具备typed路径的延迟格式化性能。

选择“项目默认”不需要在所有基准超过Foundation/spdlog。对于实际发布，仍需在应用的目标负载上测试背压、关闭和输出完整性。当前已确认的限制包括SPSC饱和p99.9约340µs、Mmap冷启动/channel准备成本和schema吞吐/尾部取舍；默认使用应依据应用的日志频率与可靠性要求，而不以局部中位改善作为保证。

Windows/macOS/Android/iOS目前具有实现和交叉编译/部分链接证据，仍缺真实设备的日志/生命周期/journal恢复资格。跨平台生产应用应先运行`tests/package_consumer/platform.zig`的目标设备自校验并补充自身故障场景。长期fuzz/sanitizer、多文件系统掉电与更多业务负载资格继续见`implementation-status.md`。

接入入口：[详细使用指南](usage.md)、[Zig包](package.md)、[生命周期](lifecycle.md)、[平台资格](platforms.md)、[std.log示例](../examples/std_log.zig)。
