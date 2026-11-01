# 普通异步与mmap异步

两种模式都在生产者线程捕获自包含事件，后台统一过滤后的交付、格式化和输出。选择只影响队列存储与恢复契约：

| 模式 | 选项 | 提交存储 | 程序崩溃后队列记录 |
| --- | --- | --- | --- |
| 普通异步 | `memory_queue` | 调用方allocator预分配的固定内存 | 丢失尚未交付记录 |
| mmap异步 | `journal` | 文件支持的共享可写映射 | 可恢复完整提交记录，允许重放 |

```zig
const runtime = try kron.Runtime.create(allocator, io, .{
    .submission = .asynchronous,
    .memory_queue = .{ .capacity = 256, .max_record_bytes = 8192 },
    .routes = &.{.{ .name = "file", .sink = file.sink(), .format = .json }},
});
```

将 `memory_queue` 替换为 `journal = .{ .path = "app.journal", .capacity = 256, .max_record_bytes = 8192 }` 即选择mmap。两选项互斥；库不会因为mmap失败自动降级到内存并改变恢复保证。未选择存储的异步初始化返回 `JournalRequired`；同步模式不接受异步存储配置。

普通异步没有journal文件、文件锁、文件预分配、文件映射或初始化文件sync；固定空间通过调用方allocator取得，初始化后capture、reserve、commit、drain不分配。allocator自身可以使用系统匿名内存机制。它复用相同有界slot/sequence/commit协议与codec，保留typed fields、嵌套快照、Secret、动态配置、采样和redaction。内存数据结构保留固定协议头用于统一状态管理，但不表示磁盘归档或恢复。

两种模式都支持共享producer和显式注册SPSC：`.submission = .low_latency` 配合 `max_thread_channels`，每个channel按照所选存储在初始化时预分配。内存模式不要求required custom sink具有跨重启身份；mmap模式仍要求。`max_journal_bytes`现为所有queue存储的总预算上限，包含共享队列与channel，名称保留兼容已有API。

`runtime.queueStorage()`/`health().queue_storage`返回none、memory或mmap。`queue_reserved_bytes`报告总queue空间；`journal_reserved_bytes`只报告文件映射空间，普通异步为零。

## 确认与可靠性

普通异步的accepted表示事件已进入固定内存队列，程序异常退出会丢失仍在队列中的记录。written仍等待所有required输出完整写出。`flush(.durable)`先排空此前日志并同步支持durable的输出文件，但不把内存队列当作可恢复journal、不生成内存durable checkpoint。新来的未排空事件仍不能抵抗进程崩溃。

直接内存queue `Journal.sync()`返回 `UnsupportedDurability`；内存配置的 `reclaim_after=.durable`返回 `DurableReclaimRequiresMmap`，不能宣称提交队列有持久回收。`recovery_versions`仅适用于mmap，内存模式返回 `RecoveryRequiresMmap`。内存schema表可用于进程内预注册与捕获优化，schema-ready不代表跨进程持久化。

mmap模式的accepted/written/durable边界沿用原协议，详见 [生命周期](lifecycle.md) 和 [平台支持](platforms.md)。两种模式都是有界queue；满时遵循block/drop_newest/fallback_sync策略。普通模式可通过 `zig build run-async-memory` 查看。

## 验证

`test-async-storage`覆盖两种frontend的内存队列、禁止文件open/create的I/O trap、源覆写快照、热配置/脱敏、初始化后零分配、满队列drop、关闭唤醒阻塞producer、schema预注册和输出文件durable。`test-async-crash`使用真实子进程SIGKILL：三条accepted/unwritten记录在内存模式丢失、mmap模式全部恢复；先前写出的三条输出在两模式都保留，正常drain也是accepted=written。

```sh
zig build test-async-storage -Doptimize=ReleaseSafe -j1
zig build test-async-crash -j1
zig build bench-snapshot -Doptimize=ReleaseFast -- --mode=attached --phase=full --producers=4 --events=10000 --storage=memory
```

基准结果始终标注queue_storage与process_crash_recovery。两模式可靠性不同，不会作为“相同语义优化”比较；重复试验原始报告位于 `bench/evidence/2026-10-31-async-storage/`。当前两模式各10次完整交付试验，分别确认100,000条written、pending/drop/测量分配为零。小规模测量不能作为稳定排名。
