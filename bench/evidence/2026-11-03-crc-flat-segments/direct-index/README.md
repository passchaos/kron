# 平坦固定段的直接scalar索引

这是初版POINTER物化重复old16KiB后的独立表示。firstsource/math/formula与所有失败证据保持；新shadow仅改变fixedWord的4个scalar访问，oldgeneralupdate/tables/extra生成、typed读取/seed/statewrite、format两调用及所有test保持。

通过comptime选择直接oldtables[row][byte]或extra[row-16][byte]，不取得row/array POINTER、不绑定1KiBrow值。目标是复用旧general已经引用的row常量；去重、rodata、加载地址、register/frame/call尚未证明。全部数值/读界/alias最小相关验证后冻结，再actual逐rowhash/address gate，通过才双拓扑140组CRC控制。无速度声明。

数学与canonical24row身份复用 [初版独立结果](../independent-math.json)，仅访问表示改变，实际newtyped执行另行绑定hash。测量使用父目录未改的 [measure_primitive.py](../measure_primitive.py) 与相同 [primitive.zig](../primitive.zig)，输出写本目录的独立window，不改初版任何source/bin/tar。

## 实际门槛与完整流程决定

Direct-index已消除初版静态重复：两个newELF的24个canonical1KiBrow各只有一处完整PT_LOAD pattern，old0..15由general与fixed共用；实际rodata两者各+8192B，无namedwholetable/extraaggregate、无任何gather。完整地址/hash见 [actual-review.json](actual-review.json)。slot局部8B PUSHrax、producer原frame/calls减少和primitiveframe+64B/额外38stackrefs均记录，不从源码balancedXOR推速度。

双拓扑CRC140组控制分别E79/P40局部lead、61/100inc，零稳定negative，checksum全部相等，因此进入完整流程。两核各320项，共640项完整async/SPSC Memory/Mmap P1/P4 batch/sampled inline/schema，逐条核验64640000物理JSON，actualmanaged/fullmetadata/原256slot512B/acceptedwritten/drop/pending核对通过。E-core208轴中79局部lead/128inc/1stable负向，written32组27lead/5inc；P-core17/190/1，written6lead/26inc。全部逐组区间与正负见 [E-core](flow-ecore/summary.json)、[P-core](flow-pcore/summary.json)。

本版按预先约定的负向gate拒绝。E-coreSPSC MemoryP4sampled inline p99为460→482ns、pairedratio0.95436；同组p999正向不覆盖p99反例，p50中位283→359ns但未过spread门槛仍inc。P-coreasyncMmapP4sampled schema p50 ratio0.95311也稳定负向。不能用27/6个written局部资格覆盖尾部反例；没有Foundationtrial或生产应用，原默认算法/3CRC/完整字段/clock/capture/borrow/pin/barrier预算仍保持。

全部positive/negative/noisy和初版零trial的存储失败保留。下一独立方案仅考察checked consumer的固定CRC、producer保原算法与调用边界，尚未实现或证明收益，不能继承本版比值。决定与完整资格见 [decision.json](decision.json)。整体Foundation两个前端目标仍未完成。
