# kron

Zig 0.16 原生日志库，提供结构化字段、同步与有界异步提交、普通文本/JSON、文件轮转、动态过滤与配置、脱敏、归档和明确的恢复边界。目标是同时降低应用开销、保持输出可读性并验证可靠性。

性能验收目标是超过 **Foundation/logging + spdlog** 和 **Foundation/logging + tracing**，在相同完整输出与完成边界下验证吞吐、生命周期和尾延迟；P-core/E-core分别测量。当前尚未全面达到，逐组结果与资格见 [前端对照](docs/cpp-comparison.md)。

当前默认 CRC、完整值域、恢复与有界队列协议保持。近期候选有局部工作量收益，但控制组或完整流程未取得保留资格，生产已恢复并增加相关边界回归。全部正负和限制见 [当前验收状态](docs/implementation-status.md) 与 [试验记录快照](docs/history/readme-performance-experiments-2026-11-03.md)。

应用从 **`kron.Logging`** 接入。默认 stderr、同步、text、info；单文件、多输出、轮转、Memory/Mmap 和 SPSC 使用同一套初始化、logger 获取与关闭方法。

当前性能结论与最新验证见 [当前验收状态](docs/implementation-status.md)、[性能试验快照](docs/history/readme-performance-2026-11-09.md) 和 [证据索引](bench/evidence/INDEX.md)。
## 快速开始

在应用构建中通过 `b.dependency("kron")` 导入模块，完整配置见 [Zig 包接入](docs/package.md)。最小程序：

```zig
const std = @import("std");
const kron = @import("kron");

pub fn main(init: std.process.Init) !void {
    const logging = try kron.Logging.create(init.gpa, init.io, .{});
    defer logging.destroy();
    logging.scoped("app").info("started", .{ .version = "1.0" });
    try logging.shutdown();
}
```

后台文件日志将 create 的选项设为：

```zig
.{
    .outputs = &.{.{
        .name = "file",
        .target = .{ .file = .{ .path = "app.jsonl", .backend = .portable } },
        .mode = .asynchronous,
        .format = .json,
    }},
}
```

这里的异步队列默认是有界 Memory。系统本地时间可在route选
`.timestamp=.{ .zone=.local }`，Linux显式启用libc支持；带 `At` 的源码位置
使用仓库相对路径，text以无引号的 `路径:行:列` 输出。输出统一使用outputs列表；
mode/queue/overflow/redaction/sampling等均逐route设置，未填写字段采用Route默认值。
完整参数、context、线程、多个输出、std.log 和关闭错误处理见
[详细使用指南](docs/usage.md)。可运行源码见 [examples/](examples/README.md)。

## 模式与完成边界

| 选择 | 适合的场景 | 契约 |
| --- | --- | --- |
| sync | 小工具、单线程、较低日志频率 | 调用线程完成编码与交付 |
| shared Memory | 常规后台日志 | 有界共享队列；进程异常退出会丢失尚未交付记录 |
| shared Mmap | 需要进程崩溃恢复 | 恢复完整 commit，允许至少一次重放 |
| SPSC Memory/Mmap | 高级可选：固定线程且应用已验证收益 | 显式 attach/detach；预分配每线程队列和普通共享队列 |

`flush()` 确认 required 输出 written，`flushDurable()` 请求适用输出与 journal 的 durable 协议，`shutdown()` 关闭入场并排空。accepted、written 与 durable 的含义不同；Mmap commit 不等于断电保证。详细协议见 [异步存储](docs/async-storage.md)、[生命周期](docs/lifecycle.md) 和 [文件可靠性](docs/file-reliability.md)。

文件输出支持 portable 和 Linux io_uring 后端。网络 sink/exporter 不在当前单机范围内。

## 文档入口

| 目的 | 文档 |
| --- | --- |
| 开始使用、查参数和生命周期 | [使用指南](docs/usage.md)、[包接入](docs/package.md)、[默认接入建议](docs/default-logging.md) |
| 理解接口与内部实现 | [接口架构](docs/api-design.md)、[代码结构](docs/code-structure.md)、[整体设计](docs/design.md) |
| 修改源码、选择测试和维护证据 | [开发与验证](docs/development.md)、[测试目录](tests/README.md)、[基准目录](bench/README.md) |
| 查能力、平台和剩余工作 | [当前验收状态](docs/implementation-status.md)、[平台支持](docs/platforms.md) |
| 查全部专题与历史记录 | [文档导航](docs/README.md)、[历史记录](docs/history/README.md) |

## 构建和示例

```sh
zig build
zig build run-quick-start
zig build run-file-logging
zig build run-rolling
zig build run-local-time
zig build run-file-stdout-local-time
zig build run-mmap
zig build run-source-location
zig build run-route-policies
zig build test-logging -Doptimize=ReleaseSafe -j1
zig build verify-local -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
```

`zig build` 安装 `kroncat` 和 `kron-bench`；依赖消费只导入库模块。`verify-local` 包括单元/集成、负向编译、真实 SIGKILL、独立包、单线程、工具与示例编译；源码分发另外运行 `test-package-distribution`。按修改范围选择的完整命令见 [开发与验证](docs/development.md)。

```sh
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
```

工具使用见 [tools/](tools/README.md)。

## 性能与发布范围

当前能力可用于固定 Zig 0.16 的 Linux 单机项目，选择 bounded Memory/portable 起步，并按应用处理过载与关闭错误。Windows、macOS、Android、iOS 有实现和交叉编译/部分链接证据，仍需实际设备运行资格；包版本为 0.1.0。

完整流程比较、双拓扑矩阵、保留/撤回候选和所有正负数据见
[当前验收状态](docs/implementation-status.md)、
[性能试验快照](docs/history/readme-performance-2026-11-09.md) 和
[证据索引](bench/evidence/INDEX.md)。当前结论：durable memory 已基本完成超越，
剩余差距集中在 P1 mmap 对 tracing；`text_format`、`MmapSpool` 与
`render_cache` 是 opt-in 快速路径，默认 durable/CRC/recovery/queue 契约不变。

原始数据、失败/慢值、各轮源码身份与局部 before/after 均保留在 evidence；历次 README 性能叙述见 [历史快照](docs/history/README.md)。
