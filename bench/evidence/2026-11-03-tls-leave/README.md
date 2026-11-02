# TLS admission 清理与 Frame 表示实验

两种候选均已撤回，生产恢复 3c1252b 的 optional BoundDecision 与完整 enter/leave 初始化。共 880 项对照，逐条核验 88,880,000 条物理 JSON。目标继续是在相同完整输出、written flush、关闭及清理边界下超过 Foundation/logging + spdlog 与 + tracing；本轮没有新的 Foundation 排名。

## 独立候选与决定

两种候选都以同一 original optional + clear 基线比较，百分比不叠加。

| 候选 | E-core 默认 16 组 | P-core 默认 16 组 | E-core schema 8 组 | 总试验/物理记录 |
| --- | --- | --- | --- | --- |
| leave 后 inactive slot 赋 undefined | 0 候选领先 / 7 基线领先 / 9 不确定 | 16 不确定 | 8 不确定 | 440 / 44,440,000 |
| 完整初始化的 64B scalar Frame | 0 候选领先 / 6 基线领先 / 10 不确定 | 1 候选领先 / 1 基线领先 / 14 不确定 | 1 候选领先 / 7 不确定 | 440 / 44,440,000 |

表中组数为未插桩 written-close 吞吐资格，40 项 PMU 另列。每组五个配对轮次，双方原始值及配对速度比 spread 均不超过 10%，95% 配对 bootstrap 区间不跨 1 才记局部领先。噪声/区间不合格的结果完整保留，不能把正向中位当验收。

inactive 清理候选的 source/lifecycle 与实际代码均安全，但 E-core 七组稳定负向，没有保留资格。完整决定在 [inactive-slot-decision.json](inactive-slot-decision.json)。候选去掉清理不作为 compact 的增量基线。

compact 的六组 E-core 默认吞吐负向均属于 SPSC：Memory P1 batch/sample、P4 batch/sample，以及 Mmap P1 batch、P4 sampled。速度比分别约 0.9732、0.9794、0.9796、0.9697、0.9711、0.9278；最后一组约慢 7.2%。P-core shared Mmap P1 batch 约 1.0621 的局部领先与 SPSC Mmap P1 sampled 约 0.9818 的负向并存；schema shared Memory P1 batch 约 1.0294 局部领先。局部 wins 与 TLS 少 1 KiB 不能覆盖默认反例，决定在 [compact-decision.json](compact-decision.json)。

## 实际代码与所有权

inactive 候选只改 leave 最后一次 slot 清理。原 Frame/owners 保持 80B/5120B；ActualFast Runtime.end 557→484B、endThread 405→329B，各少 12 条静态指令、三组 YMM load/store 及相关 vzeroupper。enter 保持 158B/35 指令。其余归一化代码、callback/depth/gate/wake 顺序、CRC 表均保持，见 [binary-review.json](binary-review.json)。少清理指令没有产生端到端收益。

compact 恢复原完整 leave 清理，只将私有 optional decision 拆为完整 u64 generations、Level 和独立 presence。DWARF 确认 Frame 80→64B、alignment 仍 8B，owners 5120→4096B，.tdata 5376→4352B，.tbss 281172B 不变；PT_TLS file/memory size 均少 1024B。不能据此声称 cacheline 对齐、RSS 少 1 KiB 或吞吐更快。

compact 的 begin/end/beginThread/endThread 分别 1269→1265、557→541、502→475、405→373B；enter 158→160B。getter 157→191B、已内联 getter 的 threadFilterDecision 554→591B；完整 .text 仅少 16B。decision 重建增加 presence 分支和标量返回写入，threadFilterDecision 不能再共用 TLS/cache 的连续 24B 返回尾部。没有新 call、栈 reservation 或 spill slot。唯一独立 getter call 仍位于 threadSnapshot 的 admitted matching-channel/resource 分支，caller 复制两版相同；不能仅以独立函数增长解释默认 SPSC 回退。详见 [compact-binary-review.json](compact-binary-review.json)。

资源 callback 期间 outer Frame 仍 active；独立 owner 可嵌套，callback 后才 reload/decrement depth、完整清理，再释放 gate/channel 并按原协议唤醒。借用 resource 不重复释放，所有 helpers 仅读 active 范围。full u32 channel、full u64 generations、空 scope 的 Some(zero decision) 与 None 区分全部保留。未加入 pointer/channel tagging、generation 截位或公开新 API。

两种候选的默认 CRC、三个校验点、reserve/schema/SPSC、releaseAdmissionView 与 channel release 控制保持。compact 实际 CRC 310 条指令及 16×1KiB 表字节与基线相同。未改变 inline v4/reference v5、捕获/时钟时点、snapshot、错误优先级、无热分配或 256 槽/512B 预算。

## 完整测量

public managed Logging；shared/SPSC、Memory/Mmap、P1/P4、batch/sampled；100,000 events + 1000 warmup、五个 typed numeric 字段、full metadata/system clock、64KiB portable file buffer、默认 CRC。每次真实文件都由独立 oracle 全量核验，随后删除成功临时文件；失败现场与原始日志保留。written flush→shutdown→cleanup，未请求 device durable。

E-core affinity 16,18,20,22,24,26；P-core 0,2,4,6,8,10。所有本轮编译/测试完成后冻结 binary，再串行测量；本轮没有同时进行编译、测试或其他重型维护。宿主整体负载较高，按每组输入 spread 和配对区间处理不确定性，不把当前窗口推广为其他宿主排名。

| compact 数据 | 试验/记录 | 内容 |
| --- | --- | --- |
| [compact-ecore-workflow](compact-ecore-workflow/summary.json) | 160 / 16,160,000 | 默认 shared/SPSC 全矩阵，六组吞吐和两组 p99.9 基线领先 |
| [compact-pcore-workflow](compact-pcore-workflow/summary.json) | 160 / 16,160,000 | 默认全矩阵，一正一负；lifecycle/p99.9 全不确定 |
| [compact-schema-ecore](compact-schema-ecore/summary.json) | 80 / 8,080,000 | shared prepared 控制，一组局部吞吐/lifecycle 领先 |
| [compact-ecore-pmu](compact-ecore-pmu/summary.json) | 40 / 4,040,000 | shared batch 全进程 instructions/cycles，计入 setup/关闭/清理 |

compact PMU instructions 配对中位约少 0.05%–0.08%，Memory 两组取得计数资格，Mmap 两组不确定；cycles 四组全部不确定，Memory P1 written-close 约 0.9616 局部负向。inactive PMU instructions 中位约少 0.12%，部分组有计数资格；written-close 全不确定，Memory/Mmap P1 cycles 有基线局部领先。静态、计数、written/lifecycle 与 tail 各自判断，全部原始正负在 results.jsonl、manifest 和 summary 中。

inactive 的 ecore-workflow、pcore-workflow、schema-ecore、ecore-pmu 原目录保持。每个 manifest 记录 executable SHA256、driver/oracle/qualification 身份与输入，source archives/patch/provenance 绑定各候选。结束测量后复查所有 compact owning source/build/binary hashes 未变，再恢复生产。基线 binary e66add4160b4a8104c2c6873ae7dd0bed82c96c6c39374960a3fd06eb20a677b；inactive a5e22027c3247bb0a280d002f33aea04bf6fad99beedede47d1b301f23d5482e；compact 9996d1eb2489fb6005c721a736b32a3ce4e08e3f15b164d0aa14eedd0fbb81c6。

复现默认对照，从相应 source archive 编译并核对 binary 身份后运行：

    python3 bench/cpp_reference/compare_versions.py --before BEFORE --after AFTER --output-dir FRESH --events 100000 --repeats 5 --affinity 16,18,20,22,24,26 --modes async,spsc

P-core 改 affinity；schema 加 --schema on --modes async；PMU 加 --perf cpu_atom --modes async --phases batch。FRESH 必须是不存在的新目录，不能覆盖本轮反例。

## 测试发现与最终回归

直接以 src/core/admission.zig 为测试根首次因 ../config/reload.zig 超出 module 路径失败，原 module-safe.log 保留。root-safe-smoke 最初只执行 14 项导入聚合检查，不能算 TLS 行为覆盖，initial-test-discovery.json 明确排除；增加 root 显式 admission 导入后，root-imported-safe 真正执行三项原 TLS 测试，17 项 total。

新增 lifecycle suite 不读私有 Frame/原始 inactive bytes，只通过 helpers 检查：owned/bare/borrowed 复用、release callback 中 outer 查询及 independent nested frames、64 层满栈拒绝 overflow 后逐层释放、同一 owner 地址的 OS 线程隔离。第五项 1050 轮覆盖全部七个 Level，0/1/max-i64/bit63/max-u64 的两组独立 generation，channel 1/64/max-u32，空/非空 scope、Some(zero)/None、overwrite/scope replacement/mismatch 与 bare reuse。

最终五项相同 suite 在原 baseline test copy ReleaseSafe、compact Debug/ReleaseSafe/ReleaseFast 中通过，每个 binary 20 项 total = 五项实际行为 + 15 项导入聚合。早期四项 suite 的 19 项 total 日志另保留，不能误记为最终五项。相关 Safe logging/transactions/deadline 九步骤 49 项通过，shared admission View 选择 19 项 total 含三个实际旧配置/错误退出 cases。所有失败与发现修正原日志保持。

恢复生产后仅保留 suite、admission/root 测试导入、test-admission-lifecycle 构建入口与文档；恢复后的最终相关 gate、Debug/Fast、View 与源码分发日志分别为 restored-safe/debug/fast/view-safe/package.log。计数与 owning source 以 qualification.json 和这些实际日志为准。生产算法未变，本轮不重复全库 SIGKILL/九目标门禁，也不把以前结果改称本轮资格。

恢复后实际结果：ReleaseSafe 12/12 步骤、69/69 项通过；Debug/Fast 各 20 项 total，五项生命周期实际执行；View 选择 19 项 total 含三个实质 cases；源码分发 2/2 步骤成功，五个 fresh consumers 的写入、源快照与脱敏核验通过。格式与 diff 检查通过。最终逐文件比较确认全部 baseline src 源码/fixture 相同，仅 admission/root 测试导入和新增 suite 除外；production canonical hashes 在 qualification.json。当前无 remote，完成后提交本地版本。

空白检查范围：生产源码、测试、build 与文档的 diff/zig fmt 检查通过。完整 staged evidence 检查会报告原始 patch 的上下文空格和原始测试日志末尾空行；这些是保留的原始 artifact，不重写其 bytes。qualification.json 单独记载检查范围，不能将其描述为所有原始文件的空白检查零提示。
