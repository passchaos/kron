# 固定20/24段平坦 slicing lookup

独立于已拒PCLMUL精确尾折叠的portable候选，baseline185e700。通用Crc32.update、旧16-row表与makeTables保持原样；另生成rows16..23共8×1024B，仅固定header20/ref24方法使用。各段仍分别输出rawstate，随后payload原update、最终原finalXOR，三CRC检查点/原队列预算/borrow与生命周期不变。

定义Z(s)=(s>>8)^T0[s&255]、Ti[b]=Z^i(T0[b])。N≥4时，raw结果为各byte的T_(N-1-j)贡献XOR；fullseed按little-endian四byteXOR到前四输入byte，无额外seed项。20B首word走row19..16，其余四word15..0；24B首word23..20，其余五word19..0。全字节/seed/合法对齐覆盖，无padding；reference reserved/hash也全部参与，不按正常值省贡献。

新表逻辑8192B，复用旧16384B，不构造完整24row副本。每word四lookup经comptime表指针和平衡XOR，20/24各20/24lookup，与原16+4/8次数相同；改变贡献组织与依赖，不能推断速度。实际rodata、旧/新load对应1024B rows、cacheline、caller/frame/call由二进制gate验证，不假设表连续或临时row无复制。

先独立bitwise IEEE与所有message/seed basis、extra全部byte值、32对齐/任意seed、实际typed双guard、真实formatgolden与分段控制。native/generic都实际执行新方法，原V2首assert要求24B，完整u64seq/gen与原u32len责任保持。随后使用同一实际format owningcaller harness覆盖70payload长度×两schema形状，双拓扑全正负，资格通过才完整managedJSON和两个Foundation前端。

当前没有性能资格，不能继承旧PCLMUL或其他候选速度比。

## 初版静态决定

row POINTER表示已在静态存储门槛拒绝，零primitive、完整JSON或Foundation试验。全部数值/读界/alias与独立数学证明通过，但actualELF额外物化旧16KiB表：general使用的oldrows0..15与fixedcaller的同16rows各有两个不同物理load地址，逐个1024Bcanonicalhash相同，两种binary都验证。新增8KiB之外又有旧16KiB重复，primitive rodata实际+24576B、reference+24672B（另96B）。

这是静态预算失败，不是速度退步；没有运行runtime rowcopy，但常量image重复已经违反no-old-table-duplication门槛。source“使用pointer而非rowvalue”不能代替实际ELF证据。slot无SUBRSP但PUSHrax预留8B局部scratch，不能称无栈占用。决定与已验证地址见 [decision.json](decision.json)，详细loadedrow审查后附；所有初版source/bin/tar/hash保持原样。

下一独立表示 [direct-index](direct-index/README.md) 将改为4个直接scalar索引表达式，不取row/array地址或绑定rowvalue；尚未证明去重成功，不复用初版静态资格或任何性能比值。

完整 [actual-review.json](actual-review.json) 包含reference16个oldrow地址对与8个新row独立hash。ref24自动生成4条AVX2gather（每条4lane）及8条scalar，共24lookup；初scalar扫描48条遗漏16gatherlane，完整slot两arm逻辑64lookup。输入实际两u32＋16B读取仍在24B界内，不能将源码scalar表达式称为scalar机器码。
