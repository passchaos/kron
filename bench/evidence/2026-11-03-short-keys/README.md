# Short-key比较实验

目标继续是在完整输出与written flush/close等价边界下超越Foundation/logging + spdlog和+tracing。所有四个生产候选已经撤回，当前field恢复到`73cbd27`；仅保留独立公共测试和build入口。没有更新Foundation排名。

基线`73cbd27`保留AVX CRC及三个校验点，inline v4/reference v5。生产候选仅让`field.checkUnique`调用私有`keysEqual`：先等长、empty/同ptr，等长4..8B比较头u32和尾u32，其余仍std.mem.eql。两个读取严格在slice内，覆盖全部字节；原逐pair TestingAudit、首次DuplicateKey和visitor调用位置保持。沒有利用静态key性质省略验证、改变树预算或新增公共proof。

上一轮静态研究已确认default的field0..4六字节key实际走两个u32短比较，沒有通用memcpy/memcmp长循环。候选想减少的是std 4..16公式的额外offset算术/重复路径，不能称为消除原本不存在的长loop。实际binary的CFG、spill与总体text需独立审查。

原字段7项测试在Debug/Safe/Fast通过。独立`tests/field_key_validation.zig`九项涵盖65,016次公开checkUnique与std.mem.eql oracle、0..17B/all offsets、每个byte突变、相同/不同指针与长度、55个首重复组合、64个树/node/depth失败组合及精确audit/order；Linux mmap/mprotect guard pages实际执行，两端有效切片位于单一可读页内，无对私有helper的暴露。Debug/Fast父日志与Safe组合日志保留，source archive包含完整测试。

候选source/binary hashes见provenance，baseline源和复用binary确认来自完全相同的生产文件。性能开始前等待所有编译和测试完成。encoder公共probe单列JSON/text/logfmt × scalar5/nested20/wide5，完整输出Wyhash/字节一致才接受；file流程使用managed、default CRC、system time、256槽/512B、64KiB portable文件、完整physical JSON核验，不请求设备durable。全部失败和负向保留，不能从少offset计算推导吞吐。

首30项encoder控制核对27,000,000次完整编码的checksum/bytes。JSON/text指令配对速度比1.057/1.056（约减少5.4%）、nested20耗时速度比约1.069且局部资格成立；scalar5不确定，text wide5约0.993×局部负向。logfmt指令约减少2.5%，nested20约1.023×局部资格。精确复测保留同三个格式/输入，避免用nested改进掩盖wide回退。

首40项shared full-file PMU逐条核对4,040,000条JSON，Memory/Mmap P1/P4用户instructions约减少0.90%–0.94%，四组局部资格。P1 cycles有局部正向，P4周期和全部吞吐仍不确定。包括完整子进程setup、输出/written close，不能把PMU换算为一般producer/consumer收益。

第二30项encoder复测再次确认JSON/text nested20约6.7%/6.4%局部收益，但text wide5约0.998×再次负向，logfmt wide5约0.988×本轮负向，其他scalar/wide多不确定。不能把nested收益覆盖所有格式/值域；后续用键长1/3/4/6/8/9/16/32/64的scalar/nested控制分离fallback成本。

初版E-core完整160项核对16,160,000条JSON，16个关闭吞吐组5个局部领先、11个不确定，没有确认负向；所有中位在1以上，其中async Mmap P4 batch约1.019×、SPSC Memory P4 batch约1.016×局部资格。每组及尾部/初始化见ecore-workflow，仍不是Foundation跨库资格。

初版P-core完整160项核对16,160,000条JSON，2组关闭吞吐局部领先、14组不确定，沒有确认负向。P1 Memory batch有0.957×负向中位但噪声超限，需保留并在最后候选定向百万条复测；P4部分正向不能覆盖它。

第二候选仅将>8B标准比较移到私有noinline helper；<4保持直接std.mem.eql，4..8保持原有head/tail。目的是约束fused热函数提前计算long fallback的工作，不新增证明或跳过字节检查。与初版独立hash/archive/patch，必须验证键长控制和实际代码再决定。

键长控制揭示首候选的广泛负向：JSON/text的1/3B scalar/nested及9/16/32/64B多数组配对速度比约0.90..0.96并取得局部负向资格。其五字段default/nested局部赢不能推广；shapes-first的54,000,000次公共编码完整checksum一致，仅速度回退。

noinline>8候选没有消除这些反例：shapes-outlined的>8B scalar/nested多数约0.88..0.95×且局部负向，整个shape workload instructions/cycles也增加。encoder-outlined仍可在六字节nested输入赢约7%，但不能覆盖一般键。该候选否决，不需要完整Foundation排名或门禁来推广。

第三个最小控制只恢复首候选并显式inline keysEqual，检查是否能恢复原std.eql调用方内联；先以binary代码段判断变化，再测键长。各实现独立archive/hash/patch，全部负向原值保留。

固定std.eql wrapper always_inline后，私有eqlBytes仍被编译器外调，shape控制的1/3B和9..64B依然多组局部负向；因此第四版本也否决。inline keysEqual的realLogger及shape `.text/.rodata/.data` 与首版逐字节一致，未重复无意义计时。

## 最终保留范围

全部候选source/patch/binary/assembly、失败和负向继续保留。累计360项完整文件版本对照核对36,360,000条物理JSON；180项encoder控制核对243,000,000次完整输出的checksum/字节。前者包含default5字段及实际文件written close，后者额外覆盖long/small scalar/nested/wide与三格式；二者不能相互替代。

production未保留keysEqual、long helper、always_inline或任何验证省略。新test-field-keys包含9项公共行为测试并进入普通test/verify-local；它通过原std实现、首/outlined/fallback候选。恢复基线后的Safe test-field-keys/test-capture/test-logging共9步骤、46/46通过，新9项另外Debug/Fast通过，Linux guard实际执行。新build依赖的源码分发资格另见retained-package-safe.log；仅tests/build变化未重复整库故障campaign，旧CRC完整门禁保持原源码身份。

目标仍未达到，`decision.json`记录候选否决与保留测试，不把default/nested某些局部win视为一般日志库提速。后续优先研究shared journal live状态/缓存行，必须先核对公开mapped进度与恢复契约，不从相邻offset推导性能。
