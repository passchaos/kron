# CRC 20/24 字节的直接尾折叠

当前为独立候选，baseline185e700。生产CRC与原目标一致，三个公开seed/segment/guard回归已保留。上一轮单lane+lookup尾和outlinedowner都失败，不继承其局部速度比。

原16B代表V=load16 xor rawu32seed，20B把tail4折到128表示最高32bit：R(clmul(V.low,C64) xor(V.high<<32) xor(tail4<<96))；24B用R(clmul(V.low,C96) xorclmul(V.high,C32) xor(tail8<<64))。C64=0x163cd6124,C96=0xccaa009e,C32=0x1db710640。原四mulR只在最后执行，不先降u32再查尾表；总5/6CLMUL。

独立Python位运算/generator/bitwiseIEEE在完整message/seed基和20000随机共20416案例通过；未作为Zig或速度证据。仅原非zeroCPUfeaturegate下exact20/24入口，其他短长度原portable16/8/byte不变，>=64原四lane/math/tail不变。每个输入load16+exact4/8，无padding/过读，无20/24/payload段合并，rawstate/finalXOR与三个check保持，不能直接lower64helper阈值。

先nativeDebug/Safe/Fast/legacy/generic独立数值basis和原segment/guard回归、实际frame/inline/caller/table身份，再70length×2header模式双topology控制。任何输入稳定negative均保留并影响保留资格，不用数学/少lookup推断速度。通过才fullJSON/defaultCRC/writtenflush/shutdown/cleanup/queuebudget以及两个Foundation实际frontends性能验收。

## 首版决定

通用 `Crc32.update` 插入 exact20/24 分派的版本已拒绝。当前完整文件中 E-core 140 组为 64 组领先、12 组稳定退步、64 组不确定；P-core 140 组全部不确定。以上计数从已结束的 summary.json 重新计算，替代早期中间汇总。64/80/96/97/112/113/128/144/145 字节附近包含负向控制；其中 schema112 的速度比为 0.8265，schema96 为 0.8404。比值大于一有利于候选。全部正负逐组结果见 [E-core](primitive-ecore/summary.json) 与 [P-core](primitive-pcore/summary.json)，决定与身份核验见 [decision.json](decision.json)。

源码、四个二进制 hash、raw 与首版 tar 保持原样。该版本没有完整 JSON 或 Foundation 试验，不更新跨库排名。下一独立候选将算法限定于 journal 固定 header/reference 段，以检查 caller 与通用分派成本；初版退步不会被删除或新测量覆盖。

实际二进制独立审查见 [actual-review.json](actual-review.json)：这些 hash 对应 update 1412→1748B、slotChecksum 156→485B，nm 与最后指令 extent 一致；早期摘要中的1856/812B无法对应这些产物，已明确作废。原>=64 arithmetic及实际loaded CRC row保持；短路径新增比较与caller内联变化均记录，不由静态尺寸推导性能。
