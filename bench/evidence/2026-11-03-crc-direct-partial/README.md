# CRC 直接余块collapse实验

尚未取得正确性、机器码或性能资格。目标保持相同完整输出/written/关闭/清理边界超过Foundation/logging+spdlog和+tracing，P-core/E-core与生命周期/尾部单独验收。

当前baseline为4e35989，production CRC与之前VEX/fullstripe/serialtail保留状态相同；之前continuation、nonzero guard、cursor/end三个版本均撤回，原始正负在2026-11-03-crc-partial-lanes。本实验不继承它们的局部速度比。

direct候选保留初始seed、原full64stripe loop、20Bheader/24Breference/payload分段、rawstate/final XOR、byte tail、默认三校验和所有目标gates，只将末段4+r个128bit lane直接折叠到最后块的位置。

| 余块 | 直接collapsed V2（T_d为IEEE域bit shift） | CLMUL数 |
| --- | --- | --- |
| 0B | T384(x1)^T256(x2)^T128(x3)^x4 | 6 |
| 16B | T512(x1)^T384(x2)^T256(x3)^T128(x4)^b0 | 8 |
| 32B | T640(x1)^T512(x2)^T384(x3)^T256(x4)^T128(b0)^b1 | 10 |
| 48B | T768(x1)^T640(x2)^T512(x3)^T384(x4)^T256(b0)^T128(b1)^b2 | 12 |

T640/T768 reflected coefficient pairs为{0x01c7569e54,0x00ae0b5394}/{0x00df068dc2,0x018cb44e58}，应由独立normal IEEE polynomial P=0x104c11db7的GF2推导测试证明，不能只靠candidate roundtrip。既有128/256/384/512系数重算一致。各输入最后仍执行原4mul reduction。默认169/241的22/32总乘法保持，理论可将nonzero的CLMUL依赖层降一层，但register pressure、constant loads和dispatch可能抵消。

优先机器码gate：r0保持原collapse数据flow，不用4lane rotation PHI；原fullstripe scalar induction无额外copy/sub；无需stackspill或额外call；const和partial load边界全部可核对。即使过staticgate也不作为runtime qualification。

基线源码/archive/primitive/reference单独冻结，primitive沿用54长度、两种schema形状、16旋转对齐、10000次CRC/batch、每invocation5batch、五配对invocations。CRC-only批次和完整物理JSON记录必须分开计数。逐组before/after checksum一致，独立std.hash/bitwise/GF2/seed/zlib作为oracle；legacy无AVX/generic等目标单独验证。

所有本轮compile/tests结束后才串行运行性能，不与heavy维护并行；各window/input/spread/置信区间/source/binary/tool/负向/失败均保留。原始patch上下文空白/log尾空行保留，source/doc格式检查单独记录范围。任何candidate只有在所有长度控制、完整output及相关tail/lifecycle证据支持后才可保留，不更新未经同轮Foundation验证的排名。

## 最终静态决定

候选正确性成立，native Debug/ReleaseSafe/ReleaseFast、legacy SSE Safe各9/9，generic Safe三项通过/一项native-only skip；五份原始日志在本目录。T640/T768的独立generator结果与45个raw seed zlib向量另在independent-math.json。没有把正确性当作性能资格。

CRC-only隔离reference/primitive已冻结；Journal保持原baseline，不包含同时研究的reserve divrem。actual full64stripe仍20条/8mul，无extra counter，r0无4lane PHI/moves，r1/r2/r3每个weightedterm的CLMUL独立且只join单V2。

但r0新增lea/shr/indirectjmp分派、case到reduction directjmp及common k128 reload。将原tailfalse test/je计入后，该控制/constant片段净多三条动态非fold指令，64B无额外stripe输入也承担分派。CRC函数1412→1840B。没有通过实验前设置的r0静态gate，因此撤回生产，不运行primitive或完整workflow，也不虚构throughput regression。源码/archive/patch/binary身份和原始验证保留，decision.json记录零performance trial，Foundation排名未变。

工作树CRC恢复4e35989逐字节原样，此实验只保留证据文档。其并行reserve候选用独立isolation/archive/binary，restore不会改变正在测量的reserve executable/source。所有数学正确与静态成本相互区分；完整性能目标仍active。
