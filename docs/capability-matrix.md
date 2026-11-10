# 能力矩阵

本页把常用的模式、存储、格式和恢复/durable 边界放在一张表里，避免从多篇专题文档拼接组合规则。默认值以 `Route` 字段为准；所有 opt-in 快速路径都不改变默认 durable/CRC/recovery/queue 契约。

## 运行模式与存储

| 模式 / 存储 | 进程崩溃恢复 | durable | 适用场景 | 主要约束 |
| --- | --- | --- | --- | --- |
| sync | 无 | 调用线程完成后可请求输出同步 | 小工具、单线程、低频日志 | 不做后台队列；timed/async 控制接口返回能力错误 |
| shared Memory | 无，pending 丢失 | 输出可 durable，队列本身不恢复 | 常规后台日志 | 有界共享队列；崩溃丢失尚未交付记录 |
| shared Mmap | 恢复完整 commit，至少一次重放 | journal checkpoint + 输出同步 | 需要进程崩溃恢复 | 需要可预分配、非 volatile 文件系统 |
| SPSC Memory | 无，pending 丢失 | 输出可 durable，队列本身不恢复 | 固定线程且已验证收益 | 显式 attach/detach；每线程预分配队列 |
| SPSC Mmap | 恢复完整 commit，至少一次重放 | journal checkpoint + 输出同步 | 固定线程 + 崩溃恢复 | 显式 attach/detach；独占恢复 |
| `MmapSpool` | 无 journal recovery | **非 durable** | P1 mmap 最高吞吐、可接受无恢复 | 无 journal/CRC/recovery/ring/consumer；单 producer 或每 producer 独立 spool/channel |

## 格式与输出

| 格式 | 输出 | 备注 |
| --- | --- | --- |
| text | 人类可读行 | 默认格式；source 位置以 `路径:行:列` 输出 |
| json | 完整 JSON Lines | 支持 inline/schema、render cache 和 text fast path |
| logfmt | key=value 行 | 与 text/json 共用字段捕获和过滤 |
| binary | 自包含 journal/archive frame | `kroncat` 可只读查询、follow 和恢复 |

文件输出默认使用 portable backend；Linux `io_uring` 为显式 opt-in。轮转支持 size、time interval 或两者任一触发；归档使用标准 zlib。

## opt-in 快速路径

| 选项 | 收益方向 | 恢复/CRC | 组合约束 |
| --- | --- | --- | --- |
| `MemoryQueueOptions.verify_crc=false` | 省掉 memory slot CRC | 仅 volatile memory；默认 CRC 保持 | mmap/recoverable journal 拒绝；只适合接受未检测内存损坏的应用 |
| `text_format` | producer 渲染最终 JSON，consumer 直接写出 | 无 journal recovery；要求 `verify_crc=false` | 单 route、JSON、async/SPSC、memory 或 `recover=false` mmap；不能与 render cache 同用 |
| `render_cache` | producer 渲染到 volatile cache，consumer 命中直接写出 | 保留 journal/CRC/recovery；cache 本身 volatile | 需要 journal；支持 shared async/SPSC 的单 route JSON inline/schema；默认关闭 |
| `MmapSpool` | producer 直接渲染进 file-backed mapping | 无 journal/CRC/recovery | 非 durable；单 producer 或每 producer 独立 spool/channel；可选 coarse timestamp |

## 完成边界

- `flush()` 确认 required 输出 written。
- `flushDurable()` 请求适用输出与 journal 的 durable 协议；不适用于 `MmapSpool`。
- `shutdown()` 关闭入场并排空；`destroy()` 是阻塞清理，要求所有用户已停止。
- Mmap commit 不等于断电保证；进程崩溃恢复是至少一次重放，不是 exactly-once。
- 物理掉电、非 Linux 设备、NFS/CIFS/FUSE 和更广文件系统仍需独立资格。

## 平台

Linux 有实际运行资格；Windows/macOS/Android/iOS 有实现、交叉编译或部分链接证据，仍需目标设备运行资格。aarch64-linux-musl 已在 QEMU 用户态执行 root suite 与 fuzz。详细边界见 [平台支持](platforms.md) 和 [当前验收状态](implementation-status.md)。
