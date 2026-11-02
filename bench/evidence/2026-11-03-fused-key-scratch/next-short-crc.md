# 下一个独立短 CRC 段候选（尚未实现）

当前production96d7497的Crc32仅bytes.len>=64进入PCLMUL4lane；20Bslot头和24Bschema ref各用portable16/8/byte切片。已搜索CRC提交/11archive/144cachecopies，未见exact16/32/48单seed128lane的trial，未归档intermediate仍不确定。prefix合并/partial-lane优化是不同机制，不能继承任何速度比。

新路径需要另建updateShort：仅在16..48B、16整倍数的bulk上load16(p) XOR{rawstate,0}，随后0/1/2次原F128，原4mul reduction；不得复用现unconditional4load64helper直接降低阈值，更不能padding或overread。保持>=64原4lane/native-byte-tail路径，short>=16后进入原portable8B/byte尾，所以20保持4serialrow0，24保持原8wayparallel尾。

16/32/48bulk分别4/6/8CLMUL，依赖约4/5/6层；新增shortswitch、SIMD-to-u32、字段布局/callee/PHI仍有成本。数学工作：20B由20lookups变4CLMUL+4lookups；24B由24lookups变4CLMUL+8lookups；241payload原32CLMUL+1lookup不改。v1percheck由32mul+21lookup变36mul+5lookup，三checks由96mul+63lookup变108mul+15lookup。这不能推lowerlatency，seed/header到payload仍串行。

错误/CRC三点、IEEE多项式/反射/rawseed/final XOR、20/24/payload原segment、queuebudget/borrow/lifecycle不变，不添加Options/禁用校验。原shorttail layout要明确保持，不复活已失败4Bbyte-tail slicing或合并prefix。

独立验证先raw16/32/48所有message/seedGF2 basis、任意u32seed、align0..31、bitwise/zlib/标准/,分段界16/20/24/32/48/63/64及完整0..512/64K控制；generic/legacy/native三优化级真实发现与guardpage边界验证。所有compile/tests结束后才primitive54长度/两header模式/双topology，任一新short/long控制稳定negative停止，正负记录完整。通过再默认CRC/fullJSON/writtenflush/shutdown/cleanup/queuebudget完整用户流程与Foundation两个真实组合验收。

此文仅独立可行性与停止条件，无SOURCE、机器码、设备运行或速度资格。它不是当前已保留的日志优化。
