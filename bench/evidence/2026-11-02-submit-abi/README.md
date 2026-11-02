# Runtime提交参数借用与单份私有Event

基线`8279ebf`。本轮保留公共`submit*`按值API和调用快照，只让Runtime内部参数借用本次调用栈：SubmissionContext从完整可选Binding改为可选schema.Ref；owner/journal仍在公开wrapper原边界校验，canonical definition仍由journal独立解析，调用方definition不可信。本次私有Event在Channel/Admission校验后复制一次，Safe阶段就地设置内部metadata；redaction保留自己的私有Event与深层scratch，callback同步消费后才销毁。

没有新的公开unchecked Event/measurement proof，没有提前或省去clock之后的最终树校验，没有新增Runtime状态、allocator调用、queue/file预算或wire/CRC/recovery版本。public Event、borrowed字段和context规则保持。

## 代码与ABI证据

生成代码逐二进制hash保存在assembly.json与各.s，数字是函数`sub rsp`，不含寄存器保存、返回地址、下游栈或完整应用峰值：

| 实现 | Destination stack | Safe stack | redaction stack |
| --- | ---: | ---: | ---: |
| before | 984B | 4024B | 41464B |
| 只借用内部参数 | 856B | 4024B | 41240B |
| 只携带Ref | 648B | 3832B | 41240B |
| 最终单份Event | 648B | 3352B | 41240B |

Context从336B对象变为约120B的实际布局。普通无binding路径此前仍在Destination搬完整可选Binding约240B，Safe入口再搬232B payload与tag；现在只保留Ref24B。单份Event再去掉Safe入口的224B对象重组。redaction仍复制自己的Event，prepared分支仍解析/处理完整canonical definition，predicate仍借用原Event调用；不能描述为所有宽拷贝已消失。

Safe机器码before7025B→单份Event5784B，Destination1127B→924B。试验过普通/Prepared额外编译拆分，Safe代码扩大至7744B；默认PMU指令减少约0.58%，弱于单份Event约0.7%，该拆分候选恢复。原候选源码在borrow-only/ref-only/single-event/split-mode patch、archive与provenance中，最终src与single-event source hash一致。

## 正确性与生命周期

capture/redaction/predicate/outputs Safe34/34通过，prepared measurement/shape/invalid binding/CRC重点21项通过。新public submission_snapshot的4项测试覆盖：

- sync/shared/SPSC×无/全局redaction，正常/filtered/error后调用者全部metadata、source/trace、各层descriptor和bytes不被改写。
- publication gap之后交付accepted前的完整快照，覆写消息、key、source、nested、bytes和format args仍不改变记录。
- forged definition仍canonical解析，非法owner/journal/ref hash/id/version拒绝和shape预留后abort边界不变，admissions、queue与旧配置pins回收平衡。
- sync/full fallback的sink内嵌套另一Runtime redaction，同owner递归拒绝，outer scratch和后续route字节保持。

public-snapshot-safe.log包含实际4/4执行，test-submission-snapshot已加入公共test与verify-local。测试只访问公共API，不公开私有上下文。Prepared predicate/shape/TooLarge顺序、caller.tree_validated不可信、clock造cycle回归都保持原约束。

## 完整文件与CPU

同一public managed file负载：系统墙钟、五typed数字、full JSON、256槽/512B、64KiB portable buffer、100k事件+1000warmup、默认CRC、written flush→shutdown→cleanup；不请求设备durable。E-core16/18/20/22/24/26与P-core0/2/4/6/8/10独立测量。

Ref-only完整shared PMU40项核对4,040,000条JSON，四组instructions约减少0.3%，吞吐不确定。最终单份Event PMU40项核对4,040,000条JSON，Memory/Mmap P1/P4 instructions均约减少0.68%–0.70%并取得局部资格；cycles只有Mmap P1局部下降（速度比约1.049），其余不确定，完整吞吐全部不确定。不能用更小栈或指令直接宣称完整日志更快。

普通/Prepared编译拆分诊断另40项核对4,040,000条JSON，instructions约减少0.57%–0.58%，P1 cycles局部下降，但没有完整吞吐资格，代码增长，因此未保留。其数值不与最终实现叠加。

最终inline双拓扑各160项共核对32,320,000条JSON。E-core16组关闭吞吐全部不确定，async Mmap P4 sampled配对中位0.961的负向保留；P-core仅async Mmap P4 batch约1.010取得局部领先，其他15组不确定。P1 sampled及p99/p99.9多个负向中位/极值保持，所有尾部资格仍不确定，不称为低尾延迟改进。

Prepared另80项完整PMU核对8,080,000条JSON，async/SPSC Memory/Mmap P1/P4六组instructions局部下降约0.5%–0.7%，两组受批次形状/波动影响不确定；SPSC Memory P4 cycles局部下降，吞吐全部不确定。SPSC Mmap P4指令有较大的正向中位但不达门限，不能外推。全部计数accepted=written、pending/drop=0，setup/cleanup包括在PMU子进程统计中，kernel不计入用户态事件。

合计520项完整版本比较核对52,520,000条JSON。所有原始报告、真实输出hash、命令、配对区间和波动在各results/summary中。E-core首轮普通矩阵与public测试编译窗口有少量重叠，已保留且不作为稳定速度承诺；之后prepared测量按冻结二进制运行。

## 最终资格

最终完整ReleaseSafe verify-local、source distribution与九目标对象门禁151/151步骤成功、630/631测试通过（1项默认未链接系统local能力skip），记录在full-safe.log；local专项实际执行UTC和六时区×五模式独立oracle。public快照4项、默认CRC、真实随机/边界SIGKILL、单线程和独立包均纳入。Object不替代非Linux设备运行，进程SIGKILL不替代物理断电。

两个Foundation真实前端须以最终同源码分别做P-core/E-core矩阵；当前局部版本比较没有建立新的跨库排名，也没有证明完整目标已经达到。最终同轮报告独立记录init、written、shutdown、cleanup、lifecycle与p99/p99.9，不能叠加本页各候选百分比。

随后完成最终同源码两个Foundation前端双拓扑320项同轮矩阵，共核对32,320,000条JSON。P-core对spdlog的16对中kron局部领先4、其余12不确定；对tracing局部领先2、其余14不确定。E-core对spdlog有3个peer局部领先、13不确定；对tracing16对全部不确定。E-core关闭吞吐目标未达到、P-core整体inconclusive，不能把波动造成的未确认差距当作已经超越。所有source/binary/来源与各阶段在[E-core报告](../../cpp_reference/evidence/2026-11-02-submit-abi-ecore/README.md)、[P-core报告](../../cpp_reference/evidence/2026-11-02-submit-abi-pcore/README.md)。

下一步安全typed capture设计在next-typed-capture.md，尚未实现。现有Event擦除类型之后不能凭一个bool恢复静态键/标量证明；下一候选必须自己构造私有字段，保留容器和format args的原clock/错误边界。

```sh
zig build test-submission-snapshot -Doptimize=ReleaseSafe -j1 --summary all
python3 bench/cpp_reference/compare_versions.py --before BEFORE --after AFTER \
  --output-dir FRESH --affinity 16,18,20,22,24,26 --events 100000 --repeats 5 --modes async,spsc
zig build verify-local test-package-distribution check-platforms -Doptimize=ReleaseSafe -j1 --summary all
```
