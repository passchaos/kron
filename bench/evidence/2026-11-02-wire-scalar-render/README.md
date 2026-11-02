# checked wire typed visitor与渲染

本轮基线5b72254包含已保留的decimal八位分块。当前候选继续针对consumer wire/Value物化成本验证，尚未给出完整速度或跨库排名。默认性能路径仍是shared Memory/Mmap，SPSC保持高级可选。

## 当前profile

before-provenance固定post-decimal完整Logging可执行文件与全部src，baseline-source.tar.xz冻结源码。四组managed shared Memory/Mmap P1/P4各100万计时事件+1000 warmup，逐条核对400.4万JSON；完整元数据/系统clock、五数值字段、256槽/512B、64KiB file buffer、4服务量子、portable/written→shutdown→cleanup，CPU0/2/4/6/8/10。

cycle/u 997Hz、DWARF16KiB用户态profile包含初始化与清理、排除kernel，不提供低噪声速度资格。Memory P1 wire.render自占约11.1%、WireInput.value约3.4%、valueInner约2.8%；P4分别约5.0%/1.5%/1.5%。样本约1K、零lost，内联边界和样本skid不能转换成某个操作的精确周期。profile输出在wire-scalar-current-profile/，raw perf.data保留于`.zig-cache/wire-scalar-current-profile/`。

## 候选边界

WireInput.valueWith(receiver)使用同一tag、长度、节点、深度、nested、重复key与arena预算检查，成功后以comptime tag和typed payload调用receiver.accept。普通value()以Materializer receiver构造原Value，外部API/错误集合保持；aggregates仍完成整个容器解析后才交给callback。没有公开unchecked pointer、复用验证凭证或删掉CRC。

Fused JSON/text/logfmt将scalar直接交给按tag编译的writer，跳过中间Value/通用tag二次分派；Array/Group仍物化其checked children。common.writeTaggedValue复用原所有scalar/quoted/hex/NaN/Inf/整数JSON精度/recursive策略，public value/event仍完整校验借用树。Schema kind mask在payload完整验证之后检查，维持malformed/truncated优先级；只有完整scratch记录成功才交给sink。metadata/deferred/binary/fallback、route binding/pin/required barrier不改。

最初typed writer生成多个独立调用，40项完整PMU的指令减少只有约0.15%，没有cycle/速度资格；source、binary、原始CSV/row/慢值归档于outlined-writers/。随后将comptime-tag writer内联，scalar helper符号消失；valueInner code size由约0x641增至0xfbc，代码增长属于被测候选取舍，不假定inlining一定更快。

## 独立oracle与门禁

将完整before/after src复制到隔离module，wire_module.zig只为独立比较暴露api与wire。differential.zig对3份flat all-scalar/UTF8/bytes/extrema、nested与最大256-node fixture，所有截断和4096次各fixture变异，共17527比较；9769个valid mutation在JSON/text/logfmt中逐字节一致。原decoder和原fused renderer各自作为独立oracle，非法/不适用wire的错误与Fallback分别对照，不以新decoder给新writer提供唯一正确性依据。最终inline版本的独立比较再次通过，结果在inline-differential-results.json。

Root Debug20/20，Safe59/59、最终Fast60/60（均包含import fixtures）覆盖融合/codec/standalone-invalid树；新增typed visitor damaged bool/整数截断/node预算/重复group测试验证callback次数为零，valid complete group只调用一次，专项Safe14/14。编译初始label/ambiguous reference、测试u3边界与inline-for控制流错误均保留，没有当作通过覆盖；完整Safe/平台/包资格在full-safe.log记录：151/151步骤、640/641项通过（1项系统local能力skip），包含源码分发、九目标对象、真实SIGKILL和全部示例。

## 完整用户态工作量

Inline版40项完整shared真实文件试验核对1204万JSON，Memory P1/P4指令中位−1.686%/−1.664%，Mmap P1/P4为−1.652%/−1.656%。四组CV/spread均达标，中位95%区间不重叠。cycles与该PMU窗口的written速度仍区间重叠，多数组波动超门限，不能作为一般throughput/latency收益。数据见inline-pmu-comparison.json及全部原始日志。after-provenance和candidate-source.tar.xz固定该版src/binary，不能把outlined窗口拼成一轮低噪声数据。
