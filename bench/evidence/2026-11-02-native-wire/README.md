# Native整数wire候选：全部撤回

**本轮没有保留v6 codec、reader、Runtime选项或默认写入改变。** 生产实现恢复`edc81ac`的inline v4/reference v5，canonical Value及完整i128/u128、CRC、journal、归档和恢复协议保持。保留真实旧writer冻结的六份v4/v5 fixture与兼容回归，以及完整候选源码、错误验证和所有性能正负值。性能目标仍是超过两个Foundation前端。

## 候选与兼容验证

候选自包含v6保留84B header，新增physical signed64=11/unsigned64=12，能fit对应i64/u64的值使用9B tag+payload，宽值继续17B；schema v2/v5、裸writeValue仍用wide128。两种整数tag映射回原canonical signed/unsigned，公共JSON字节保持。v6对宽tag承载native范围值拒绝InvalidValue，旧1/3/4和schema2/5对新tag在读payload前InvalidTag，完整读取/节点/深度/arena与duplicate错误顺序保持。

五个u64数值载荷从85B降到45B，精确少40B。固定slot stride、预留队列内存和JSON文件字节没有减少，不能把载荷小20%左右直接当作应用吞吐提升。

由真正`edc81ac`归档源码构建的旧writer生成v4 scalar/wide/nested/deferred及v5 definition/reference六份fixture。四个旧v4逐字节重编码一致；候选迁移v6后所有metadata/value/JSON一致；frozen v5 payload、metadata hash和v4 self-contained表示仍精确相同。`v4-fixtures.json`、`v5-fixtures.json`、`fixture-reproduction.json`绑定旧来源、generator与每份SHA256，全部六份用旧writer重新生成后逐字节相同。

候选根Debug native专项22/22与codec58/58通过，单分派Safe68/68，专门化与fused/v5重点Safe24/24、后期69/69通过（包含import检查，非唯一测试总数）。11种inline/reference corpus保留原8种并新增native+wide/nested/deferred，3680截断、22528变异，合法数据按实际版本精确再编码；Reader11份文件各两次导出，原文件不变。真实mapped Runtime混合旧v4/newv6 commit恢复与后续live事件检查通过，public async storage8/8；Python envelope/CRC旧4、新6、reference5限定与负向oracle13/13通过。

这些结果证明候选对应范围的兼容性，**没有完整发布门禁、真实v6 SIGKILL或掉电资格**。候选在性能筛选中被否决，未进入最终全量发布/跨库/应用矩阵。最初shadow局部变量、窄整数测试算术和其他编译失败均在实验日志保留，修复后才取得相应通过结果。

## 完整性能筛选

基线为`edc81ac`的冻结source和ReleaseFast reference binary。full JSON、五typed数字、系统时钟、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup；不请求device durable。E-core CPU16/18/20/22/24/26。所有记录被独立oracle逐条核对，accepted=written、pending/drop=0。

| 候选 | 试验 | 核对物理JSON | 核心结果 |
| --- | ---: | ---: | --- |
| 首版v6，async/SPSC P1/P4 Memory/Mmap batch/sampled | 160 | 16,160,000 | 多数配对中位负向，4组关闭吞吐peer局部领先，其他不确定 |
| 单次size/write分类＋inline header写入，shared完整PMU | 40 | 4,040,000 | instructions约+1.3%，四组局部负向；cycles部分负向 |
| 全树/renderer按native模式专门化，shared PMU | 40 | 4,040,000 | instructions约+1.7%，四组局部负向；吞吐正负混合/不确定 |
| 共享metadata、仅属性循环专门化，shared PMU | 40 | 4,040,000 | instructions约+1.3%–1.4%，Memory/Mmap P1周期及吞吐有局部负向 |
| 分阶段Runtime默认v4、显式可选v6，shared PMU | 40 | 4,040,000 | 默认instructions约+2.5%，四组局部负向；P4 cycles也局部负向 |

总320项核对32,320,000条完整JSON，默认CRC全部保留。更少bytes没有消除动态分类、额外mode分派/函数复制/代码布局成本。即使最后将v6设为可选，其reader和mode支持也增加默认路径成本。因此全部生产候选撤回，不以只读兼容、局部payload收益或某个正向中位替代完整性能要求。没有同轮Foundation排名，不把它称为当前生产的新排名。

源码身份分别在initial/single-dispatch/specialized/staged provenance与patch/archive，最终撤回前完整src/tests/build/docs在`final-withdrawn-source.tar.xz`与`final-withdrawn.patch`。专门化生成代码去掉了逐value native flag，但曾使codec.decode代码体增约88%、text段增约2%；这些静态事实不是收益资格。

## 保留的回归

当前src只保留`core/tests/codec_frozen.zig`、所属test import、schema_codec中frozen reference回归及六份真实fixture。所有生产编码/解析函数、Runtime/Logging选项、构建与Python恢复oracle回到原实现。Safe与Debug冻结fixture筛选各16/16，包含两个真实named回归；codec Fast52/52通过。旧v5明确拒绝11/12，原v4同样没有新tag。`retained-*.log`只证明当前保留范围，不继承候选的v6资格。

下一阶段需要从实际typed捕获/调用ABI与header/字段验证的工作量定位收益。只缩小已擦除类型的value representation并新增分类，未证明有利于E-core。重复的prototype成本/负向不能被重新包装成“轻量wire必然更快”。

```sh
# Reproduce the actual old writer fixtures from the archived baseline.
zig build-exe -O ReleaseSafe --dep kron -Mroot=bench/evidence/2026-11-02-native-wire/freeze_v4.zig \
  -O ReleaseSafe -Mkron=ARCHIVED_EDC81AC/src/root.zig -femit-bin=FIXTURE_WRITER
FIXTURE_WRITER scalar > v4_scalar.bin
FIXTURE_WRITER schema-reference > v5_reference.bin
zig test src/root.zig -O ReleaseSafe --test-filter 'frozen v4' --test-filter 'frozen v5'
zig test src/root.zig -O ReleaseFast --test-filter codec
```
