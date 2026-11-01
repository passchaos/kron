# kron

面向 Zig 0.16 的日志库，目标是同时提供低调用延迟、结构化事件、可读输出和明确的崩溃恢复语义。

面向 Windows、Linux、macOS、Android 和 iOS 的单机日志库：同步、内存异步与 mmap 异步提交，文本/JSON、动态过滤、文件轮转、归档、恢复和性能验证。网络 sink 与 exporter 已移除。实际证据与剩余工作见 [实现验收清单](docs/implementation-status.md)。

公共接口仅提供 Zig API，包依赖和应用生命周期见 [Zig 包接入](docs/package.md)。

常用接入使用 `kron.Logging`，统一管理单个或多个输出与底层 Runtime；默认 stderr、同步、text、info。完整参数、结构化字段、线程、Memory/Mmap、std.log 桥、轮转和错误处理见 [详细使用指南](docs/usage.md)。

```zig
const logging = try kron.Logging.create(init.gpa, init.io, .{});
defer logging.destroy();
const log = logging.scoped("app");
log.info("started", .{ .version = "1.0" });
try logging.shutdown();
```

这里的 `init` 是 Zig 0.16 的 `std.process.Init`，应用导入 `const kron = @import("kron")`。完整程序见 [quick_start.zig](examples/quick_start.zig)。后台文件日志设置 `.output = .{ .file = .{ .path = "app.jsonl", .backend = .portable } }`、`.mode = .asynchronous`、`.format = .json`，默认采用有界 Memory 队列，见 [file_logging.zig](examples/file_logging.zig)。

固定Zig 0.16的Linux单机项目可将kron作为项目默认日志实现，优先选共享异步Memory与portable文件后端，按应用确定过载策略并显式关闭。选型、std.log桥和资格边界见[默认日志接入建议](docs/default-logging.md)。

完整方案见 [整体设计](docs/design.md)。该文档汇总了多语言日志库调研，以及性能、mmap、io_uring、动态 filter 和可靠性的最终决策。

## 核心方向

- 结构化事件优先，支持 typed fields、context、脱敏和 trace 关联。
- 默认输出普通文本或 JSON Lines，支持直接查看和现有日志采集系统。
- 异步提供两种存储：`memory_queue` 使用固定内存，`journal` 使用文件支持的共享mmap；后台统一格式化并写出。
- 普通 logger 使用共享有界队列；显式注册的低延迟 logger 使用每线程 SPSC channel，两者均可选择内存或mmap。
- 进程崩溃后恢复完整提交但尚未写出的记录，不依赖 crash handler 排空普通内存队列。
- 明确区分 `accepted`、`written` 和 `durable`；抵抗断电需要同步持久化确认。
- Linux 提供可选 io_uring 批量写入后端，并保留普通批量写入后端。
- 源码 `c4b7f34` 的完整Memory/Mmap同轮对照中，io_uring中位低于portable约17%–19%；实际后端验证、完成边界和负载限制见[io_uring对照](bench/evidence/2026-11-01-uring-current/README.md)。后续批次合并同时改善两种后端，当前后端排名仍需新一轮同轮对照。
- 支持环境变量、运行时 API 和配置热加载；常用 filter 不在每条日志上解析配置或读取环境变量。
- 内存、journal 空间、线程 channel 和在途 I/O 均有明确预算。

## 配置示意

```bash
KRON_LOG='info,http=debug,db.query=trace,noisy=off' ./app
```

运行中的进程通过显式 reload/API 更新规则；另一个 shell 中修改环境变量不会改变已经运行的进程。

## 构建和运行

```bash
zig build
zig build verify-local -Doptimize=ReleaseSafe -j2
zig build test-single-threaded -Doptimize=ReleaseSafe -j1
zig build check-platforms -j1
zig build test-package -Doptimize=ReleaseSafe -j1
zig build test-package-single-threaded -Doptimize=ReleaseSafe -j1
zig build test-package-distribution -Doptimize=ReleaseSafe -j1
zig build test-runtime-crash -Doptimize=ReleaseSafe -j1
zig build test-platform-host -Doptimize=ReleaseSafe -j1
zig build test-decoder-matrix -Doptimize=ReleaseSafe -j1
zig build test-regex-differential test-regex-fuzz -Doptimize=ReleaseSafe -j1
zig build test-regex-equivalence -Doptimize=ReleaseSafe --fuzz=1M -j1
zig build run-quick-start
zig build run-file-logging
zig build run-structured
zig build run-local-time
zig build run-file-stdout-local-time
zig build run-threaded
zig build run-rolling
zig build run-basic
zig build run-async-memory
zig build run-std-log
zig build run-configuration-sources
zig build bench -Doptimize=ReleaseFast -- --mode=spsc --producers=4 --sink=file --backend=portable
zig build bench-dispatch -Doptimize=ReleaseFast -- --iterations=100000 --repetitions=5
```

`zig build` 安装 `kroncat` 和 `kron-bench`；库通过 `dependency.module("kron")` 导入。`verify-local` 与 `verify` 覆盖单机单元/并发/工具测试、负向编译、真实 SIGKILL 恢复、独立包消费、单线程可执行文件、回归工具和示例编译。源码分发包另外通过 `test-package-distribution` 验证。具体单项 gate 可用 `test-integration`、`test-crash`、`test-query`、`test-adapter` 和 `test-compile-fail`。

```bash
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
zig-out/bin/kroncat --json --where 'request_id == "abc"' app.kron
```

常用接口见 [使用指南](docs/usage.md)，多输出与轮转同样使用 `Logging`，见 [rolling.zig](examples/rolling.zig)。`Logging` 拥有全部配置的文件/轮转输出和底层 Runtime，调用者停止所有用户后 destroy 一次。底层扩展示例见 [basic.zig](examples/basic.zig)；单独使用 `Runtime` 时，它默认借用传入的 sink，必须先停止/销毁 runtime，再销毁 sink。journal 模式的 required custom sink 需要显式稳定 `recovery_identity`，文件输出已自动提供绝对路径身份。

默认多线程构建的 `flushUntil`、`flushRoutesUntil` 和 `shutdownUntil` 接受单调时钟 deadline。超时返回后已提交操作仍可继续，资源保持存活。单线程构建支持同步日志和普通 flush/shutdown；带 deadline 的控制操作返回 `TimedControlUnavailable`，异步/SPSC 模式返回 `ThreadsUnavailable`。详见 [生命周期与 deadline](docs/lifecycle.md)。

显式开启 v2 schema 表后，可预注册 scope、格式串与字段形状，减少热路径重复 metadata 捕获。共享/SPSC logger 都支持，见 [schema 与预注册](docs/schema.md) 和 `zig build run-prepared`。

文件轮转支持大小与单调时间间隔；trace/span 信息可写入本地文本、JSON 和归档。

新增生产能力：

- [配置热替换](docs/configuration.md)：旧事件保留原交付目标，资源lease完成后释放。
- [批次配置复用](docs/batch-configuration.md)：后台同版本日志共用受保护View，失败保留记录与资源引用。
- [批内确认与统计](docs/batch-accounting.md)：预计算durable路由需求，聚合已确认记录的written计数，错误保留准确前缀。
- [就绪批次合并](docs/coalesced-delivery.md)：在原64条服务量子的预算内合并最多256条就绪记录，共享输出屏障，逐条校验和回收。
- [schema消费者融合](docs/schema.md)：至少64条就绪记录、单JSON/text/logfmt目标、无模板参数时直接读取已验证定义和值；短窗口与其他形状保留原路径。
- [路由过滤性能](docs/route-filter-performance.md)：配置期派生level掩码，保留scope覆盖和旧版本决策。
- [异步存储选择](docs/async-storage.md)：普通内存异步与mmap异步，共同接口、明确恢复区别。
- [消费者服务预算](docs/consumer-scheduling.md)：Memory/Mmap共享与SPSC队列的有界轮询，默认四个64条服务量子，可按负载选择一到四个。
- [SPSC空间通知](docs/consumer-scheduling.md)：满队列producer等待本队列进度，保留全局关闭/worker错误通知和原服务顺序。
- [文件可靠性](docs/file-reliability.md)：部分写入、轮转、显式durable和恢复边界。
- [Mmap冷发布](docs/mmap-publication.md)：Linux全文件同步覆盖映射脏页，减少重复发布操作并保留schema就绪与故障边界。
- [嵌套字段](docs/structured-values.md)：显式array/group，固定遍历预算和递归脱敏。
- [编码与归档](docs/encoding.md)：全树验证、长度计算与二进制framing的共同路径。
- [记录编码校验复用](docs/encoder-validation.md)：完整text/JSON/logfmt只校验一次字段树，保留独立value入口、原格式和错误边界。
- [数字与转义输出](docs/decimal-output.md)：专用十进制、宽整数分块和直接字符串转义，保留原格式及流式短写边界。
- [时间处理](docs/time.md)：UTC/固定偏移、日期与时长、RFC3339解析输出和同秒缓存，不使用夏令时。
- [字段捕获](docs/capture.md)：静态命名字段、动态key与context路径的契约和对照测量。
- [压缩归档](docs/compressed-archive.md)：标准zlib block，kroncat只读查看与follow。
- [字段与正则过滤](docs/predicates.md)：接受前固定决策，固定状态NFA不回溯。
- [正则匹配工作量](docs/regex-performance.md)：配置期展开断言与空转移、位图活跃状态、业务输入对照和覆盖率引导fuzz。
- [全局采样](docs/sampling.md)：精确预算、配置更新相位与专门路径的实测边界。
- [资格化TSC时钟](docs/tsc-clock.md)：显式选择、硬件/校准检查，失败回退到原生时钟。
- [性能回归](docs/performance-regression.md)：固定输入、多次重复和子进程 affinity，噪声过高时报告 inconclusive。
- [应用影响基准](docs/application-benchmark.md)：相同计算工作量的无logger/Memory/Mmap对照，独立核验应用结果与完整JSON，报告CPU/cache与关闭成本。
- [提交热点优化](docs/performance-hotspots.md)：native PCLMUL CRC、decoded delivery 校验复用和单 JSON/text/logfmt route 的 fused wire-to-record；其他形状回退，完整重复测量与尾延迟限制保留。

本地组件的调研与复用边界见 [本地仓库复用评估](docs/local-reuse.md)。
Windows/Linux/macOS/Android/iOS 的实现、构建与运行验证边界见 [平台支持](docs/platforms.md)。

## 调用路径与性能

最新源码`e8bd353`与Foundation Logging真实spdlog前端＋Rust后台完成 **200项同轮完整Memory/Mmap对照、2020万条JSON核对**。普通inline SPSC的Memory P1/P4吞吐中位2.342M/2.391M条/s、Mmap2.322M/2.360M，分别高于Foundation8.67%/3.21%和23.09%/12.58%；全部完整关闭吞吐跨库组仍因波动超门限inconclusive，shared Memory P4仍落后4.41%。schema多数配置较慢，SPSC p99.9约345–347µs和Mmap P4初始化约1.25秒仍有差距。完整阶段、资源、慢值和资格见[新同轮详细报告](bench/cpp_reference/evidence/2026-11-01-e8bd353-foundation/detailed-comparison.md)及[说明](bench/cpp_reference/evidence/2026-11-01-e8bd353-foundation/README.md)。后面的历史与局部before/after数据保留自己的源码身份，不叠加成当前跨库排名。

常规 `scoped()` 保留运行时时钟注入。`loggerWithClock(kron.StandardClock, scope)` 静态选择标准 I/O 时钟，`loggerWithClock(kron.NativeClock, scope)` 在 Linux 直接使用 vDSO-aware clock_gettime；`ZeroClock` 省略墙钟时间戳。SPSC 对应 `attachThreadWithClock`。静态路径仍复用相同字段、filter、journal 和交付语义。

`std.Io` 用于显式应用环境、初始化、平台等待与 portable 后端；mmap reserve/commit 不经 I/O vtable，Linux io_uring 是直接内核接口。性能报告区分前端分位数、批量平均、最终 written drain 和 durable flush，见 [基准方法](docs/benchmark-methodology.md)。现有小规模结果不是“业界最快”的证据。

归档 [C++/Foundation完整工作流对照](docs/cpp-full-workflow.md) 包括spdlog 1.17、Quill 13.1、本地Foundation Logging和对照时的kron源码快照，统一完整JSON并分别报告调用延迟、written flush、关闭和启动。300个实测试验逐条验证3030万条日志；该快照的kron尚未领先，大多数性能指标仍受host波动影响。后续native PCLMUL CRC、decoded delivery校验复用、fused wire-to-record和配置View/批内统计均有独立before/after证据。2026-11-01负载窗口同轮复测已完成120个试验、1212万条记录验证，全部组因spread超门限标inconclusive；同轮中位数显示P1 kron领先、P4 Foundation略领先，稳定排名仍需宿主安静窗口复测，数据见 `bench/cpp_reference/evidence/2026-11-01-pclmul-same-round/`。

[业界实现与优化方向](docs/industry-performance-lessons.md)记录从Quill/Foundation实际源码、fmtlog/NanoLog/Reckless/BqLog设计中确认的机制，按完整流程profile推进批处理、配置复用与CRC工作量优化。

此前仅Memory/Mmap对照使用源码`182fc9e`默认配置同轮比较Foundation真实spdlog前端＋Rust后台：120项试验、1212万条完整JSON核对。Memory中位kron领先，Mmap单producer中位领先、四producer仍落后；Foundation组波动均超门限，mmap初始化与SPSC调用尾部仍有差距。数据与证据见[该轮Memory/Mmap完整报告](bench/cpp_reference/evidence/2026-11-01-memory-mmap-current/README.md)，不以更早源码数据推导当前排名。

此前源码`4447fe6`另完成Foundation（真实spdlog前端＋Rust后台）、独立spdlog和kron的140项完整文件流程同轮对照，1414万条JSON逐条核对。kron本轮中位高于独立spdlog，仍未全面超过Foundation：P4 Memory约落后9%，P4 Mmap稳态接近，SPSC Mmap完整生命周期初始化成本较高；波动与未资格范围见[该轮完整报告](bench/cpp_reference/evidence/2026-11-01-current-workflow/README.md)。

当前就绪批次合并与基线 `45f5ec1` 完成240项完整文件试验、2424万条物理JSON逐条核对，保持系统时钟、完整字段、原队列/文件预算和最终written flush/关闭/清理。Portable Memory四组中位提升4.4%–10.0%，其中三组bootstrap中位区间不重叠；Mmap多数组仍inconclusive。独立io_uring P4 Memory中位提升14.2%/23.6%，共享Memory的p99也出现负向，不能声称所有尾延迟改善。完整ReleaseSafe门禁93/93步骤、540/540测试和九目标对象编译通过；原始慢值、未完成测量、额外消费者栈与恢复证据见[批次合并报告](bench/evidence/2026-11-01-coalesced-delivery/README.md)。两种后端的独立捕获窗口不提供新的后端或Foundation排名；后续候选优先级见[业界实现与优化方向](docs/industry-performance-lessons.md)。

后续schema融合以 `366adc3` 为基线完成最终240项完整文件与40项完整PMU对照，另20项百万条P1复查，共5630万条物理JSON核对。Prepared Memory P4共享/SPSC吞吐中位提升6.35%/8.03%，通过本轮重复性门限且中位区间不重叠；schema用户态指令减少约1.8%–1.9%。Mmap多数组与调用尾部仍inconclusive，P1长流程Memory/Mmap负向中位0.65%/1.39%、区间重叠，原慢值保留。最终完整ReleaseSafe门禁93/93步骤、545/545测试与九目标编译通过。原始候选、否决的指针版本、中断捕获、额外消费者栈和最终资格边界见[schema完整对照](bench/evidence/2026-11-01-consumer-post-coalescing/README.md)；不据此宣布新的跨库排名。

共享admission进一步直接持有已验证的配置View，结束时释放reader，accepted记录保留独立pin。正式370项完整文件/PMU/百万条复查核对5437万条JSON；shared schema Mmap单producer长流程中位提升4.79%，重复性通过且置信区间不重叠。其他路径没有一般收益资格，PMU shared Memory四producer负向中位3.36%也保留。被否决的文件缓冲callback候选及admission数据分别归档；当前结果和并发lease验证见[admission View对照](bench/evidence/2026-11-01-admission-view/README.md)，新的跨库结果见本节最新同轮报告。

SPSC满队列现在等待本队列的进程内space epoch，避免由其他队列进度触发重复等待；原队列服务顺序、CRC/配置引用与确认边界保持。正式400项完整文件/PMU/百万条对照核对8440万条JSON，Memory inline SPSC四producer长sampled p99.9中位366.312→340.708µs（−6.99%），通过本轮重复性门限且中位区间不重叠；普通吞吐、p50/p99与Mmap尾部多数未资格。每Journal对象增加64字节、队列/file预算和分配次数不增。原短流程P1负向与所有慢值保留，诊断计数和并发唤醒证据见[队列进度报告](bench/evidence/2026-11-01-queue-progress/README.md)；这不是新的Foundation同轮排名。

当前prepared优化通过556项完整ReleaseSafe测试和九目标对象编译。Prepared提交在原全树校验中测量动态value/nested key字节，只在本次未改写调用中复用；公开reference codec、canonical/ready引用、CRC/pin/barrier继续校验。380项完整文件/PMU/百万条对照核对6438万条JSON，schema用户态指令减少约4%，shared Memory单producer长batch吞吐中位+4.89%，重复性通过且区间不重叠。P1长sampled p99.9负向、P4和Mmap多数未资格，全部慢值和限制见[prepared测量报告](bench/evidence/2026-11-01-prepared-measure/README.md)；不以局部收益推导当前跨库排名。

## 实施顺序

1. 固定事件、字段、配置和可靠性契约，建立 Zig 0.16 构建骨架。
2. 实现同步 text/JSON、过滤、context、脱敏与基础文件 sink。
3. 实现自包含 journal 格式、提交协议、恢复工具和崩溃注入测试。
4. 实现基于 journal 的异步后台、flush、checkpoint 和 shutdown。
5. 增加每线程 SPSC、延迟格式化优化和动态配置缓存。
6. 实现 Linux io_uring 后端、轮转和公平的性能基准。
7. 增加可选二进制归档、flight recorder 和生态适配。

各阶段的验收标准、未承诺能力和风险边界详见 [整体设计](docs/design.md)。
