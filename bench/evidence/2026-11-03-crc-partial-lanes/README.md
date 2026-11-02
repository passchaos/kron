# CRC partial-lane continuation 实验

这是尚未取得性能资格的独立候选。完整目标继续是在相同输出及完成边界下超过 Foundation/logging + spdlog 与 + tracing。基线和输入身份在 baseline-provenance.json，源码只有 src/platform/crc32_pclmul.zig 的 16B 余块布局改变；不复用 TLS、prefix CRC 或 byte-tail slicing 的百分比。

原实现先把四个 lane collapse，再串行处理剩余 16B 块。候选先用已有 512-bit 系数延续仍有新块的 lane，按最后块的时间顺序轮转，再执行原 384/256/128-bit collapse 与最终 reduction。

| 完整 64B stripe 之后 | collapse 输入 |
| --- | --- |
| r0，0B | x1, x2, x3, x4 |
| r1，16B | x2, x3, x4, F512(x1,b0) |
| r2，32B | x3, x4, F512(x1,b0), F512(x2,b1) |
| r3，48B | x4, F512(x1,b0), F512(x2,b1), F512(x3,b2) |

F512 的距离是 512 bits，和原完整 stripe 的 lane 延续相同。乘法数量保持：241B inline 的 240B bulk + 1B byte tail 为 32 次 CLMUL，169B schema 的 160B bulk + 9B tail 为 22 次；拟减少的是 reduction 前末段的串行依赖层数。r0、短输入和 64 KiB 长输入是控制，shuffle、branch、register pressure 和最终 compiled code 成本必须实测。

原 IEEE polynomial/reflection、任意 32-bit seed、final XOR、bulk/tail、20B header→可选 24B reference→payload 三次独立 update 及所有 journal 校验点不变。feature dispatch 仍是原 PCLMUL/SSE2 与 128-bit AVX/legacy，未加入 YMM 路径。invalid raw helper 的输入仍不在其 >=64B、16B multiple 前置契约内。

正确性使用独立 reflected bitwise state machine、各消息/seed GF2 基向量、所有 raw 64..512 的 16B 倍数与 alignment 0..31、任意 seed、Python zlib 冻结向量；CRC wrapper 的原长度/partition oracle 另保留。benchmark primitive 对每个输入先用 std.hash.Crc32 全量核验，timed checksum 由 before/after 再逐组一致性检查。

primitive.zig 保留原 journal-crc 工作量，仅将长度集合扩展为 54 类：两种 header/reference 形状、16 旋转对齐、每批 10000 条、每进程五内部批次。measure_primitive.py 运行五次配对独立进程；外层轮次使用内部中位统计，双方/比值 spread <=10% 且 95% bootstrap 区间不跨 1 才取得局部资格。E-core CPU30 与 P-core CPU10 分开，原始输出、错误、source/binary/tool hashes 和噪声都保留。

所有本轮编译/测试结束后才启动性能，不能由 dependency graph、静态少指令或 selected primitive win 推断完整日志更快。跨长度结果支持继续后，才在保持 default CRC、完整 JSON、written flush、shutdown/cleanup 的流程中对照。实际结果与最终保留/撤回决定将在本目录补充；目前没有新 Foundation 排名。

## 首候选原始结果

unconditional switch 的 E-core primitive 108 组中 60 组候选局部领先、16 组基线领先、32 组不确定；P-core 106 组不确定、两组 64KiB 长控制局部领先。两拓扑各 5400 个原始批次样本，全部 checksum 配对一致。E-core 241B inline 约 1.1133、169B schema 约 1.0511，但 bulk128/192/256 的 r0 与 byte-tail 控制有稳定负向，192B inline 约 0.9475。该版本不具备跨长度保留资格，尚未扩展到完整 workflow，全部正负在 primitive-ecore/pcore 和 unconditional-decision.json。

实际 reference 的 CRC update 1412→1568B，完整 .text 876205→876349B；r0/r1/r2/r3 通过四项间接 jump table 分派。r0 相对原 test+je，额外承担索引、indirect jump、两个 vector register moves 和 direct jump；这个控制/寄存器片段净多四条动态非fold指令。非零余块有一次 k512 reload；默认 22/32 次 CLMUL 数量不变，无新call、栈reservation或spill。静态证据解释一个可测试成本，但不是完整吞吐结论。

下一 guarded 变体仅显式检查 len!=0 再进入非零 switch，试图让 r0 绕过间接分派；不加 branchHint 或其他机制。编译器可能重新合并，所以必须先核对新 binary，再用新的目录保留所有矩阵。首 source archive、patch、after-bench/after-reference 与 owning provenance 不覆盖。

## 正确性与测试发现

native CRC 模块 Debug/Safe/Fast 各 9/9，legacy PCLMUL 无AVX Safe 9/9；generic Safe 三项通过/一项 native-only skip。最初 native结果来自完成的工具结果，completed-tool-results.json 明确该范围；legacy/generic 原始日志单独保存，未为转写日志重复测试。相同三个新oracles在独立原始基线副本 Safe 中通过，总五项实际测试。

首次 root 筛选只通过 15 项 aggregate imports，没有三项真实 partial CRC cases，parent assertion 拦截测量；原 root-discovered-safe.log 与 first-test-discovery.json 排除出行为资格。补充按 x86_64+PCLMUL+SSE2 控制的 test-only direct helper import 后，root-explicit-helper-safe.log 实际执行三项新cases，总18项通过。generic/non-x86 不强制解析不支持的asm，未扩大生产API。

## Guarded 原始结果与进一步控制

guarded 两拓扑各 5400 原始批次全部 checksum 一致。E-core 108 组为50候选领先/7基线领先/51不确定；P-core 108组全不确定。bulk128/r0控制仍有稳定负向，不能因169B schema的局部正向推广。该版本尚未运行完整日志workflow，决定和全部原始数据在 guarded-decision.json 与 guarded-primitive-*。

actual guarded CRC 无间接 jump table，但 r0 控制段六条动态指令对原两条；full64stripe 22条对原20条，每轮多一次counter copy和subtraction，另有preloop初始化。非零partial的lane moves从2/2/2变4/3/3，动态CLMUL仍22/32；无新call/spill，tables/三个CRC检查/队列控制保持。详见 guarded-binary-review.json。

第三 cursor/end variant 单独检验循环迭代表示：预先计算remainder和完整块终点，p从initial64之后按64前进至full_end；原fold math、partial guard/rotation、reduction和oracles不变。迭代数仍floor(bytes.len/64)-1，不推断更少记账会更快。旧两个source/archive/binaries/results全部不覆盖，待新正确性与actualcodegen后再启动新矩阵。

## 最终决定

三个生产候选均撤回，恢复 cafa135 的原 full-stripe loop、原四lane collapse 后 serial F128 tail。默认 CRC、三检查、poly/seed/reflection/final XOR/header/ref/byte-tail、所有值域、queue预算和恢复格式保持。新三个独立 test cases 与 capability-gated root imports 保留；before同组新oracles Safe五项实际通过，避免候选自证。

| CRC primitive variant | E-core 108组：候选/基线/不确定 | P-core 108组：候选/基线/不确定 |
| --- | --- | --- |
| unconditional partial switch | 60 / 16 / 32 | 2 / 0 / 106 |
| explicit nonzero guard | 50 / 7 / 51 | 0 / 0 / 108 |
| cursor/full-end loop | 17 / 12 / 79 | 4 / 0 / 104 |

共32400个timed batch samples，每批10000次CRC组合，各版before/after checksum全部一致。这是CRC primitive单位，不能描述为3.24亿条真实日志。没有开展新full JSON workflow或Foundation排名，final-decision.json记录范围，所有正负/噪声与每个stage source/binary/hash/compiled controls保留。

cursor虽将full stripe降到19条，compiler重新合并成jump table，r0控制段七条对original两条；<16B tail重算bulk16多mov+and，169/241同样承担。E-core已有短/header和r0控制负向，不能以更少loop指令推广。actual source/math/seed/bounds和控制审核通过，CRC本身正确，但正确性不替代性能。详情在cursor-binary-review.json。

生产恢复后将核验CRC native/legacy/generic、root真实发现、owning Debug/Fast与源码分发，具体日志为restored-*.log。仅测试辅助函数/新cases和root test-only imports保留，不因未变生产重新跑全库SIGKILL/平台faultgate。完整Foundation双拓扑及完成/尾部目标继续active；后续独立研究不继承这些候选的任何速度比。

恢复后实际结果：CRC native Safe 9/9、无AVX legacy Safe 9/9、generic Safe 3pass/1native-only skip；owning Debug/Fast各5/5，root Safe 18/18中三个partial cases实际执行，15项为aggregate imports。源码分发五fresh consumer模式的2/2步骤成功，source snapshots/redaction核验通过。逐文件检查确认src只有CRC测试附加和root test-only imports，与cafa135的生产逻辑相同；qualification.json记录hash与所有最终日志身份。原始patch上下文空白/原始log尾部空行保持，源码/文档的diff检查单独选择范围。当前无remote，本地提交即可回溯。
