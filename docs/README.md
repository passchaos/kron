# 文档导航

从 [使用指南](usage.md) 开始接入，从 [当前验收状态](implementation-status.md) 判断能力与资格，从 [开发与验证](development.md) 开始修改仓库。公共应用入口是 `kron.Logging`，底层 API 和设计研究在各专题中说明。

## 使用与能力

| 主题 | 文档 |
| --- | --- |
| 初始化、logger、字段、线程、输出、错误 | [使用指南](usage.md) |
| Zig 依赖、构建、源码分发、单线程消费 | [包接入](package.md) |
| 项目默认日志的选择 | [默认接入建议](default-logging.md) |
| borrowed/owned、字段捕获 | [capture](capture.md) |
| array/group、显式对象适配 | [结构化值](structured-values.md) |
| 动态 filter、来源事务、旧配置资源 | [配置](configuration.md) |
| 条件与有界正则 | [predicate](predicates.md) |
| 全局采样、phase 与 bypass | [采样](sampling.md) |
| UTC/固定偏移/系统local、RFC3339、日期和时长 | [时间](time.md) |
| Memory/Mmap 的选择 | [异步存储](async-storage.md) |
| flush、durable、deadline、shutdown | [生命周期](lifecycle.md) |
| 文件短写、轮转、同步与错误锁存 | [文件可靠性](file-reliability.md) |
| 四种编码与协议版本 | [编码](encoding.md) |
| 标准 zlib 压缩归档 | [压缩归档](compressed-archive.md) |
| 预注册 metadata/schema | [schema](schema.md) |
| 平台实现、编译与设备运行 | [平台支持](platforms.md) |

## 架构与开发

| 主题 | 文档 |
| --- | --- |
| 统一 owner 与 tracing 设计映射 | [接口架构](api-design.md) |
| 目录职责、依赖、测试位置与扩展边界 | [代码结构](code-structure.md) |
| 常用 gate、精细验证与证据维护 | [开发与验证](development.md) |
| 整体产品目标、协议与验收要求 | [整体设计](design.md) |
| Journal 槽位、CRC、恢复与所有权协议 | [Journal 协议](journal-protocol.md) |
| 已有能力、最近门禁、剩余优先级 | [当前验收状态](implementation-status.md) |
| 本地项目调研与复用边界 | [本地复用](local-reuse.md) |
| 示例、集成/故障测试、基准与工具 | [examples](../examples/README.md)、[tests](../tests/README.md)、[bench](../bench/README.md)、[tools](../tools/README.md) |

## 性能机制与测量

这些文档各自保留测试时的源码与负载身份。局部 before/after 不推导当前跨库排名，inconclusive、失败与负向结果继续保留。

| 范围 | 文档 |
| --- | --- |
| 计时边界、输入与复现 | [基准方法](benchmark-methodology.md) |
| 完整业务计算和无 logger 基线 | [应用影响](application-benchmark.md) |
| 完整 C++/Foundation 工作流 | [完整对照](cpp-full-workflow.md)、[对照复现](cpp-comparison.md) |
| 回归统计与噪声 | [性能回归](performance-regression.md) |
| 机制调研、优化优先级 | [业界参考](industry-performance-lessons.md)、[热点](performance-hotspots.md) |
| 消费者公平性与队列通知 | [调度](consumer-scheduling.md) |
| 配置、确认与批处理 | [配置复用](batch-configuration.md)、[统计确认](batch-accounting.md)、[批次合并](coalesced-delivery.md) |
| route 掩码与过滤工作量 | [路由过滤](route-filter-performance.md)、[正则](regex-performance.md) |
| Mmap 发布与时钟选择 | [冷发布](mmap-publication.md)、[TSC](tsc-clock.md) |
| 编码校验、数字与转义 | [校验复用](encoder-validation.md)、[十进制](decimal-output.md)、[ASCII](ascii-output.md) |

## 历史与证据

[history/](history/README.md) 保存旧设计草案、README 的历次性能叙述和详细验收 chronology。原始日志与冻结源码仍在 `bench/evidence/`、`bench/cpp_reference/evidence/`、`tests/power_loss/evidence/`；完整目录见 [证据索引](../bench/evidence/INDEX.md)，历史快照不作为当前使用接口。
