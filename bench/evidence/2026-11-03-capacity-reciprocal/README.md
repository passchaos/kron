# 固定容量的精确倒数除法实验

当前独立数学候选，baselineHEAD61222f5，尚未Zig测试、集成或性能资格。入口特化因额外栈/temp失败，源码仍原样；本方案不从前序候选比值叠加收益。

对非零完整u64除数d，创建时M=min(floor(2^64/d),2^64−1)。对完整u64分子n，h=high64(n*M)，r0=n−h*d，c=(r0>=d)，精确q=h+c/r=r0−c*d。d>=2的M误差<1，d1截为maxu64误差=1；n<2^64使q−h为0或1，h*d<=n所以无underflow/overflow。无需每坐标pow2kind/ctz或泛型owner/sretABI变化，hot实际mul/校正成本仍需测。

独立Python233591个boundary/multiple/powers/max+200k随机案例与整数divmod一致，不是Zig正确性或性能证明。后续纯模块应由独立/,%,bitwise/seededfullu64 oracle验证商/余数，descriptordefault零不能视为validM，Journal手工省略时应正确fallback原除法而非信任伪magic。

集成前先实际验证全u64/d1/任意capacity精度、native/generic/aarch64乘法lowering及布局。Journal可能增请求空间，必须如实测算，不因padding猜size；不可弱化CRC/gen/length/schema/borrow/reclaim/error顺序。只留plainprivateinline运算，不改publicOptions/格式/整数值域，失败源码/结果独立保留。

独立Zig数学模块nativeDebug/Safe/Fast与genericSafe各3项通过，native /,% oracle覆盖200kseededpairs/fullu64 powers±1/multiples/bound和d1；根筛选实际三case发现执行（18total含15aggregate），不是仅imports。Journal新默认divideraxis在baselinecopy只移除不存在字段reset，断言/实际环回/CRCvalid损坏保持，baselineSafe17项与candidateDebug/Safe/Fast/genericSafe17项均实际两case通过。相关journal筛选81项通过（含3数学cases），未泛化为整库验证。所有source/module/binaries仍隔离，compile结束前不测性能。

## 最终决定

纯数学方案在完整u64上正确，原3个独立模块cases与native/generic三优化级、20万随机/boundary均通过；Journal同真实8cap/sharedSPSC/2^32/max/abort/defaultM0与CRC有效genbad回归、generic也通过，relatedjournal81项通过。但这不替代性能。

实际高位乘法为MULX、低位为IMUL，q校正SBB，r校正CMOVAE+subtract，仅2mul、无软helper/第三mul。reserve/SPSC没有newcall/frame/spill，validator保持0x58/两原CRC+readycall，drainframe保持0x9e28。Journal832B对原768B(+64)，divideroffset504，多个后续热字段+8，verify772/mode773移至下一cacheline，必须作为真实对象预算成本。

两topology queue各400rawbatch（每100000iterations）checksum/seq/pending全部核验，Ecore7组稳定基线领先/1不确定，Pcore6稳定基线领先/2不确定，速度比约0.90..0.94。该版本不符合容量性能门槛，撤回并保持零fullJSON/Foundationtrial。原source/archive/mathmodule/equations/正负/counterexample与实际objects全部保留；不将未使用的纯模块加入生产来冒充日志优化。

原生产Journal/tests/root逐文件与HEADf11771b相同，workspace从未应用candidate。Aarch64-fno-emit测试只属于跨目标语义检查，实际native/Aarch64 export对象另编译并hash，没有设备运行资格。CRC及全周期actual检查的静态范围在binaryreview，因physicaltable布局不能以连续16KiBhash推16rowidentity。
