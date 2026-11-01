# 文件写入、轮转和恢复边界

FileSink按完整record接受字节，portable后端使用显式offset处理短写。每段成功写入推进实际offset；零进展返回WriteZero，磁盘满返回NoSpaceLeft。部分写入后的错误锁存，后续write/flush/shutdown不会盲目重复已写前缀。Runtime的required route遇到错误会保留完整journal record，停止后台交付并返回错误；best_effort失败计数但不阻止其他required目标确认。

6项外部故障测试使用真实文件和mmap journal：成功前缀实际落盘，验证offset、健康计数、锁存错误、commit标记、CRC和待交付序号。所有owner停止后，由应用显式重建输出，再启动新Runtime重放完整记录；库不会自动truncate或修复损坏输出。journal用于保留可重放事件，不能把部分输出当作已确认完成。

## 普通轮转与durable

大小/时间轮转只等待旧文件的用户态缓冲和在途I/O完成，然后移动归档名称并打开新active文件。普通written不隐式请求fsync或F_FULLFSYNC，因此不会因为文件系统不支持strictdurable而永久停止普通日志。

显式 `RollingFileSink.sync()` 执行：当前file data strict-sync → 已知仍保留的archives逐个strict-sync → 最后parent directory strict-sync。启动时记录存在的regular archive，成功轮转后更新固定存在表；不使用的retention槽可为空，已跟踪归档缺失则报错，不返回虚假的durable成功。每次只打开一个archive descriptor，sync不分配堆内存。

`path`和`path.N`文件集合由sink独占，禁止其他进程修改、替换或删除受控archives。retention是明确的数据过期策略；durable保证只覆盖仍保留的文件，不保留已按retention删除的旧日志。轮转多次rename不是文件集合的单次事务，期间I/O失败会锁存并保留现状，不会自动猜测恢复已移动的文件名。

FileSink的 `syncData()` 仅确认file data；`sync()`还要求父目录协议。平台报告 `UnsupportedDurability` 时不破坏ordinary written能力，真正InputOutput/NoSpaceLeft等错误继续锁存。Windows与Apple实际能力边界见 [platforms.md](platforms.md)，不能把协议存在当作设备已通过掉电资格。

已退休配置在没有record pin并完成required written barrier后，会尝试可用的额外durable收尾。若静态sink能力与实际能力变化不符而返回UnsupportedDurability，配置仍可回收，同时全局历史durable资格永久撤销；真实I/O错误保留版本和lease供重试。这样不把可选收尾变成配置槽的永久占用，也不假定旧输出已durable。

## 外部reopen

外部rename后调用 `reopen()` 会先drain旧文件，尝试strict file-data sync，再打开新active。它不接收外部目标目录，关闭旧descriptor后无法确认外部目录项持久化，所以成功reopen会永久取消该sink实例的历史durable资格；之后普通write/flush继续工作，sync返回UnsupportedDurability。已有borrowed Sink的静态能力字段即使为true，live sync也会检查此状态。

如果应用要求外部归档durable，应由应用显式同步其目标文件和目录并负责生命周期。当前接口不推断外部目的地，也不声称旧file-data同步已经覆盖了外部目录。

## 故障与恢复验收

```sh
zig build test-file-delivery -Doptimize=ReleaseSafe -j1
zig build test-recovery-campaign -j1
zig build test-runtime-crash -Doptimize=ReleaseSafe -j1
```

轮转定向测试覆盖strict不支持时written仍可轮转、无隐式sync、archive sync顺序、tracked missing、reopen资格、I/O错误锁存和OOM清理。带种子恢复campaign使用16-slot journal，随机written数量64–127、pending数量1–7及配置切换位置，区分自包含/预注册schema；确认存在跨代pending后实际SIGKILL，检查written前缀和恢复后缀、source/nested/secret、CRC及重复inspection不改文件。

campaign随机化工作负载和epoch边界，在精确READY点杀进程；不是任意时刻故障采样，也不是物理断电。子QEMU系统停机证据与不同平台设备资格另行报告。

## 正常运行期间随机终止

`test-runtime-crash` 使用两个真实 producer，共享 MPSC 和独立 SPSC 各覆盖自包含载荷与预注册 schema。每个 producer 先提交 64 条并等待协调线程确认 written 前缀，随后继续提交可变长度字符串、嵌套字段、bytes 和敏感值。驱动在 READY 后按种子生成的 8–75 ms 时间 SIGKILL 子进程；提交线程与后台写出线程持续运行，没有固定 reservation/commit 停点。这个测试包含确认管道与刻意的负载间隔，不用于性能测量。

每次公开 emit 返回 accepted 后，producer 才发送 ACK，再开始下一次调用。独立 Python oracle 要求所有完整 ACK 都存在于完整 JSON 输出或独立 `kroncat` 恢复结果中；调用返回与 ACK 之间仍有一个观察窗口，所以每个 producer 允许至多下一条未确认的完整事件。测试不能知道被杀瞬间尚未确认调用的返回状态。它另外验证 warm 前缀已写出、每 channel 序号递增、稳定事件身份、数据快照、递归脱敏，以及 Python zlib 独立检查的 header/slot CRC 和完整 commit 集合。

written 与 recovered 可重叠，但相同事件身份必须有相同 payload；同一结果内重复或身份冲突均失败。若输出结尾有未写完整的记录，它必须是某条完整恢复记录的字节前缀，不能把损坏尾部当作成功日志。两次独立 inspection 必须输出完全一致，journal 与原输出哈希保持不变。原始文件在临时目录内保留到检查结束，工具不会修复或消费它们。

32 个 ReleaseSafe 普通种子及 8 个 u64 上界种子已通过，覆盖 109,419 条完整 ACK、69 条恢复记录、4 条输出/恢复重叠，并观察到 11 个未完成 reservation。writer、reader 和库模块均由项目构建传入相同优化级别，正式 ReleaseSafe/ReleaseFast 门禁各 12 个场景通过。该轮没有观察到部分输出尾部；尾部校验存在不等于这一故障分支已经被随机试验命中，真实短写资格仍来自前述文件故障测试。原始结果见 `bench/evidence/2026-10-31-random-process-crash/`。另有 6 项负向 oracle 测试确认遗漏、快照破坏、重复、身份冲突、ACK 缺口和 CRC 损坏会被拒绝。

随机时间只提供被测负载和宿主上的进程崩溃采样，不能穷举所有指令边界，也不证明系统停机、其他文件系统、设备断电或非 Linux 平台资格。种子固定负载和请求延时；实际进程调度与终止位置仍可能变化，报告分别记录请求与实际延时。

2026-11-01参考编码优化后的完整ReleaseFast门禁再次运行随机campaign，seed=20261036共享/schema场景命中1950字节未完成JSON尾部；测试确认这段字节是独立恢复完整记录的前缀，全部ACK仍由完整输出/恢复覆盖。这是当前源码实际命中的运行期部分写入证据，日志与源码身份保存于 `bench/evidence/2026-11-01-schema-encoding/`。前述52场景JSON报告保持原始记录，不改写成命中该分支。
