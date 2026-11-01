# 正则匹配工作量与资格边界

日志过滤使用固定预算的 Thompson NFA，保持 128 状态、32 层编译嵌套和 8192 字节输入上限。配置编译期计算四种开头/末尾断言条件下的可达状态，匹配时只遍历消费字符的活跃状态；两个 64 位位图合并路径，不分配内存。空分支、nullable 循环、跨 64 位边界的状态、任意字节和严格末尾 anchor 保留原语义。

`State.closure` 保存 BOL 为 false 时的两个 EOL 条件，`Regex.initial` 保存输入首位置的两个 EOL 条件。每次消费字符后的状态已经使用下一位置的末尾条件展开；只有第一位置可通过 BOL。编译期固定点在已 patch 的本正则图中计算，不读取同一 Predicate 内其他正则的状态。运行期不再逐字节展开 jump/split/assertion，也不扫描全部状态数组。

该选择把工作移到配置初始化并增加固定内存。当前 native x86_64 `Pattern` 从 4624 增为 9264 字节，`Predicate` 从 17952 增为 25632 字节，包括 64 条规则的固定 metadata 容量；8KiB 配置字符串预算保持。1000 次编译的批次探针中，API 路径约从 0.88µs/次增为 2.04µs/次，127 字面状态约从 1.15µs/次增为 3.22µs/次。此探针没有首次初始化分位数资格；资源数据与原输出见 `bench/evidence/2026-11-01-regex-active/resources.log`。

## 业务基准

```sh
zig build bench-regex -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5
python3 bench/regex_compare.py --before /path/to/frozen-before \
  --after /path/to/frozen-after --output /path/to/new-report
```

八类输入包含 API 路径、severity 消息、长字面量 search、nullable 循环、重叠 alternation、128 状态上限、密集字符类和 NUL/high bytes。每组四种输入中两种应匹配、两种应拒绝；长输入减少循环次数且保留四种输入。分别报告 Pattern、单字段 Predicate 和两类完整同步 JSON 路径。同步路径包含捕获、字段验证、predicate、JSON 编码、完整字节 hash/copy、written flush；检查 accepted/written/filtered、零初始化后分配、最终 JSON 字段与 before/after 全部输出 hash。它不覆盖异步队列、文件 I/O、durable 或单次 producer 分位数。

对照驱动固定 CPU，五对子进程交替运行，每进程五次重复，反转用例次序；检查行数、输入量、匹配量、written、输出量、hash 和测量环境相同。缺失/重复行、错误计数、输出变化和测量期分配都必须失败。全部慢样本保留，任一侧 CV 或 relative spread 超过 10% 时报告 inconclusive。

当前对照所有最终组均为 inconclusive。中位数显示 API Pattern 约 350→76ns、severity Pattern 486→79ns、长字面 search 48.5→9.5µs、重叠 alternation 142→54µs、128 状态输入 370→14µs；两类完整同步 JSON 批均约 557→282ns 与 681→283ns。这些只描述本轮数据，不能作为稳定端到端性能承诺或跨库排名。正式原始报告位于 `bench/evidence/2026-11-01-regex-active/context-comparison/`。

另五对整个基准子进程的user PMU包含八类Pattern/Predicate、两类完整同步JSON、配置编译/初始化和报告输出。全部输入计数、written和JSON hash一致，指令中位减少81.34%，两侧relative spread均低于0.00005%；cycles仍超噪声门限。长输入匹配占此探针的大部分工作，不能把该指令比例推广到异步或文件日志工作流。原始计数见`bench/evidence/2026-11-01-regex-active/pmu/`。

## 语义与 fuzz

```sh
zig build test-regex-equivalence test-regex-differential test-regex-fuzz \
  test-predicates test-regex-bench -Doptimize=ReleaseSafe -j1
zig build test-regex-equivalence -Doptimize=ReleaseSafe --fuzz=1M -j1
```

独立 dense 固定点解释器通过 8192 次 mutation 检查生产匹配器，另检查 Predicate 多正则共享数组的非零起始 offset。它只提供图执行对照；解析和最终匹配语义仍由独立 Python bytes `re.search` oracle 核对。模块测试覆盖每种字节、128 状态、32 层嵌套与 anchor 循环。

`test-regex-equivalence` 含原生 Zig coverage guided fuzz 入口：任意正则编译输入、合法复杂图与任意匹配输入、任意 predicate 配置和诊断 offset。`--fuzz=1M` 是有界运行；`--fuzz` 可由专用测试环境持续执行。ReleaseSafe 保留 Zig 边界/整数检查，覆盖率插桩由 Zig fuzzer 负责。这不代表 AddressSanitizer、ThreadSanitizer 或跨平台设备 sanitizer 资格，有限 campaign 也不能替代长期持续 fuzz。
