# Journal 固定校验段候选

这是 baseline185e700 上的第二独立候选。第一版通用 update 分派已因 E-core 稳定反例拒绝，源码、原始正负和实际代码审查保留在 [首版记录](../2026-11-03-crc-direct-tail/README.md)。

本候选只在 `format.checksum/checksumV2` 的 20B header 与 24B reference 调用精确折叠；`Crc32.update` 完整原样，payload 仍独立调用原 update。20/24 数学沿用已独立验证的完整 GF2/seed 公式，通用 native >=64 与 generic portable 原路径保持。Reference 原有 `std.debug.assert(len == 24)` 的语句与位置不变；所有模式的合法输入都是24B。源码保留非24B分支，但违反前置断言在 ReleaseFast 也没有定义行为，不能承诺该分支结果。

固定段方法、真实 format 调用的多seed/多payload/对齐/guard 与 golden 先验证，随后核对实际调用、frame、通用 update 全字节及每条真实 load 使用的常量/1KiB CRC row。Primitive 用同一 harness 在两版直接调用 format，不以 raw helper 或通用长度分派替代 owning caller，完整 checksum 消耗并对照 std oracle。70长度×两schema形状在双拓扑分别保留全部正负。资格通过才进入完整 JSON 文件、默认 CRC、written flush、shutdown、cleanup、256slot/512B 的同轮流程；整体 Foundation 两前端目标继续独立跟踪。

## 测试域纠正

父最初根据参数为 slice 错误地要求 Fast 任意长度 reference 结果保持。实际 baseline `checksumV2` 已有 `std.debug.assert(reference_bytes.len == 24)`；Zig 0.16 `assert` 在 false 时执行 `unreachable`，ReleaseFast 下仍是优化器前提。首次 Fast 试验的非法长度 oracle 比较失败已保留在 worker-native-fast.log，属于超出原合法域的测试，不能为其弱化产品前提或判定数学错误。测试将修正到合法24B，保留原断言、三个校验点和错误责任。

## 双拓扑决定

固定段版本已拒绝。E-core 140组中95组领先、21组稳定退步、24组不确定；P-core140组全部不确定。169B两种形状局部提高约20.2%/29.4%，但默认241B两种形状均不确定；192B非schema速度比0.8806、240B非schema0.8905等控制稳定负向。全部逐组正负见 [E-core](primitive-ecore/summary.json)、[P-core](primitive-pcore/summary.json)；比值大于一有利于候选。不能用169B的局部收益替代默认和边界控制。

两窗口共14000个CRC计时batch，checksum完整消耗且before/after全部相同；没有完整JSON/Foundation trial。生产未推广，通用update与旧算法保持。四份native二进制与源码、compiler hash已冻结在 [provenance](candidate-provenance.json)，与第一版的harness不同，速度比独立。

测试按实际具名case核对：native Debug/Safe/Fast及legacy Safe各8项相关case通过，generic Safe5项typed/format/guard通过且原CPU-gate实际SKIP。复用此前未变方法的通过记录均逐case说明；非法域失败、中间断言版、anonymous-only筛选与generic wrapper资格检查失败均原样保留，详见 [test manifest](worker-test-manifest.json)。没有把raw-helper在主机的generic执行算portable资格。

拒绝理由、完整负向控制与资格范围见 [decision.json](decision.json)。下一步转向shared提交协调成本；不会以关闭默认CRC、减少检查点或增加默认队列预算换取胜出。

独立 [actual-review.json](actual-review.json) 确认通用310条指令/1412B、42条实际CRC row引用与16个独立row值在四binary中相同；固定header/ref为5/6CLMUL，slot156→485B、frame32→16。Primitive直接调用相同format入口，候选suffixvector预备/栈load与caller布局改变均记录；它们不构成速度资格。三个语义CRC检查点及已检查的consumer/renderer/checkpoint/abort controls保持。
