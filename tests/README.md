# 测试组织

测试分为生产模块单测、公开API集成、真实进程/子VM故障、独立Zig消费和证据oracle。构建step统一从仓库根运行，精细选择见 [开发与验证](../docs/development.md)。

## 范围与入口

| 类型 | 所在位置/fixture | 验证 |
| --- | --- | --- |
| 模块与内部回归 | `src/` 内test、[core/tests](../src/core/tests/runtime.zig)、[logging/tests](../src/logging/tests.zig) | 字段/codec、token/gate、配置缓存、批次、错误/allocator；由根模块纳入 |
| 公共日志管线 | runtime/capture/adapter/redaction/async_storage integration | 真实sync/shared/SPSC，typed快照、context、无分配与错误 |
| 并发共享producer交付 | [async_storage.zig](async_storage.zig)、`test-async-storage` | 4线程×250记录×2轮、Memory block queue、accepted=written=1000、pending=0；Safe/Debug/Fast与5 seeds |
| 字段键与错误顺序 | [field_key_validation.zig](field_key_validation.zig)、`test-field-keys` | 独立eql字节oracle、精确pair/node计数、重复与cycle/depth/budget先后、Linux两端真实guard page |
| 队列精确峰值 | [journal_peak.zig](journal_peak.zig)、`test-journal-peak` | Memory/Mmap普通/schema并发持有量与高水位、Full/oversize/abort/CRC失败、恢复重建与完整序号/数据 |
| written进度与发布 | [journal_progress.zig](journal_progress.zig)、`test-journal-progress` | 未sync实时offset72、leading tombstones、CRC失败前缀、recovery旧tail/newgap、acquire观察后join前marker断言 |
| Journal/archive随机fuzz | [journal_fuzz.zig](journal_fuzz.zig)、`test-journal-fuzz` | 20,000随机commit/peek/release、mmap reopen/recovery、随机archive record count/message round-trip；seed打印、Debug/Safe/Fast；扩展100-seed ReleaseSafe扫描100/100通过 |
| v1/v2 journal升级兼容 | [journal/schema_journal_tests.zig](../src/journal/schema_journal_tests.zig)、根test/`test-logging` | 真实v1/v2 header/extension、CRC、commit/peek、reopen/recovery在V3源码下读写；未释放记录恢复 |
| 旧二进制journal fixture | [fixtures/journal](fixtures/journal/README.md)、根test/`test-logging` | 提交`5b1fd7c`实际二进制写出的v1 journal与v2 schema journal；待恢复记录在V3源码`recover=true`下读取并解析旧scope/message |
| nested/轮转/schema组合恢复 | [logging/tests.zig](../src/logging/tests.zig)、根test/`test-logging` | prepared nested group/array经rolling输出与mmap schema journal；flushDurable/shutdown后同journal reopen、pending=0与replay追加 |
| Clock与Io调用边界 | [clock_dispatch.zig](clock_dispatch.zig)、`test-clock-dispatch` | 精确clamp、callback内/外切换、Io身份/参数快照、zero/monotonic、public函数指针与capture/full边界 |
| TLS admission生命周期 | [admission_lifecycle.zig](../src/core/tests/admission_lifecycle.zig)、`test-admission-lifecycle` | owned/bare/borrowed复用、回调中的outer所有权、64层栈与溢出、OS线程隔离、全部Level与完整generation/channel边界 |
| 原生CRC数学与目标选择 | [crc32_pclmul.zig](../src/platform/crc32_pclmul.zig)、[crc32.zig](../src/platform/crc32.zig)；根筛选 `partial CRC stripes` | 独立bitwise/GF2消息和seed basis、任意seed/alignment、冻结zlib、prefix/partition；helper仅在x86_64+PCLMUL+SSE2测试目标导入 |
| CRC分段与读边界 | [crc32_segment_tests.zig](../src/platform/crc32_segment_tests.zig)、`test-crc-segments` | 任意u32 seed和0..512/32对齐、原20/24段及增量切分、Linux两端PROT_NONE边界与空slice |
| ASCII短尾与公共转义 | [escaping.zig](../src/encoder/escaping.zig)、`test-escaping-tails` | 独立标量首匹配、全字节/相邻pair/尾部跨界；五种公共操作逐缓冲容量的成功字节与失败前缀 |
| fused scratch生命周期 | [wire_scratch_tests.zig](../src/encoder/wire_scratch_tests.zig)、`test-wire-scratch` | JSON/text/logfmt错误和Fallback后的完整decode复用、准确比较次数、64顶层key/精确nested预算及后缀守卫 |
| 共享/SPSC坐标与证据 | [journal/tests.zig](../src/journal/tests.zig)、`test-journal-coordinates` | 八容量独立递增slot/generation oracle、非二次幂环回、跨2^32及max_sequence、reserved header/commit payload/abort/release与written；独立重算有效CRC下generation错误仍拒绝并保留槽位 |
| 配置与deadline | configuration_integration/transactions、route_policy、route_filter、predicate、deadline | 旧route版本/lease、admission、采样相位、timeout资源与reentrancy |
| 时间与source | time_integration、local_time_integration/oracle、独立package tests | exact纳秒、固定/local cache、DST/恢复身份、repo-relative source路径 |
| 文件/归档/解码 | file_delivery_failures、compressed_archive、decoder_matrix/fuzz、tool_query | partial/zero/CQE错误、版本/损坏、只读Reader/query/follow |
| 多文件系统行为 | [multifs-volatile证据](../bench/evidence/2026-11-03-multifs-volatile/README.md) | tmpfs上mmap journal按设计`VolatileFilesystem`拒绝；ext4五模式通过；非crash/掉电资格 |
| 正则 | regex_differential/fuzz/equivalence | Python差分、有界mutation、coverage-guided入口；不同资格范围分别记录 |
| 负向编译 | [compile_fail/](compile_fail/)、[run_compile_fail.py](run_compile_fail.py) | 不支持输入/格式、字段选择边界、禁止直接改opaque配置 |
| 进程恢复 | crash_writer/recovery、async_storage_crash、recovery_campaign、runtime_crash_campaign | 真实SIGKILL，完整commit/预留缺口/热route、随机ACK覆盖 |
| 子VM停机 | [power_loss/](power_loss/README.md) | QEMU停机及journal/output确认；当前HEAD V3 schema 4-run campaign（ACK 3/8/17/31）、XFS/Btrfs/F2FS schema 4-run campaigns与单次非schema ACK1通过；具体文件系统/设备，非物理断电普遍资格 |
| aarch64 QEMU用户态 | [aarch64-qemu证据](../bench/evidence/2026-11-03-aarch64-qemu/README.md) | aarch64-linux-musl static root suite 455 pass/7 skip/0 fail；journal/archive fuzz 20 seeds；独立package consumer五模式与qualification通过；非真实设备 |
| 独立包与设备宿主 | [package_consumer/](package_consumer/build.zig)、[package_consumer.py](package_consumer.py) | b.dependency、五模式、single-thread、local选项、源码分发与目标原生自校验 |
| 基准工具oracle | `test_*.py`、time/local oracle | 拒绝不完整输出、后端fallback、错误比较/回归结果，独立应用模型 |

## 验证原则

最小test证明对应行为后再升级到相关组合或最终gate。测试不因被重定位而改断言、伪造module或扩大private公开面；共享fixture仅在保持责任与oracle独立时复用。

同一个测试binary中的导入聚合test会计入总数，跨binary计数不是唯一测试数量。无libc根测试的local skip是具体能力检查，`test-local-time`必须实际运行转换/consumer与oracle。

真实故障记录保留ACK、物理JSON、完整性/FIFO和重放身份。Memory丢失未交付记录是契约，Mmap至少一次重复是允许边界；normal shutdown或只读重开不冒充SIGKILL/系统断电。平台对象/链接不冒充目标设备执行。

临时文件与缓存使用 `.zig-cache` 或由fixture拥有的临时目录，保留失败现场时记录其身份。冻结历史结果位于 `bench/evidence` 与 `power_loss/evidence`，不会被当前测试路径整理改变。

`independent_outputs.zig`（`zig build test-outputs`）验证Logging.outputs独立mode/queue/overflow、逐route采样与队列前脱敏、partial success、64输出、thread/prepared回滚与deadline关闭。`test_managed_outputs_compare.py`校验完整流程基准的JSON oracle，拒绝漏项、重复、截断与工作负载改变。

`submission_snapshot.zig`（`zig build test-submission-snapshot`）验证public submit对调用者Event/各层borrowed backing的不可变性、accepted前队列快照、public Binding的canonical查找与非法引用拒绝边界，以及sync/full fallback内嵌套sink回调的redaction scratch生命周期。该step纳入test与verify-local，不通过公开私有measurement proof来验证。
