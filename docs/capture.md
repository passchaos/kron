# 命名字段捕获与context

普通logger没有附加context时，字段直接捕获到最终描述数组。命名struct和tuple的长度在编译期已知，栈描述符按实际字段数预留、最多64项；动态slice/指针保留64项预算。成功后消息、key、string/bytes和嵌套descriptor仍借用至同步编码或异步accepted前完成复制，不因为直接捕获放宽生命周期。

命名struct的成员名由Zig保证唯一，`fields.appendFields`只在必要时将新key与既有prefix比较，不再重复比较同一struct的已知不同成员。旧prefix仍完整校验，新value按原顺序检查，attributes共用节点预算。动态Field tuple/slice、数组与nested group继续检查重复key，空输入也不会跳过已存在的无效prefix。

静态类型明确为scalar的命名成员现在直接计入一个节点，不再经过动态Value验证派发；`fromAny`仍校验支持类型，节点预算在原顺序推进。`Value`、array/group和optional容器继续完整递归验证。已有prefix与动态key输入保持原校验。捕获结果不作为可复用证明：时钟回调可能改写借用字段，因此runtime在predicate/reservation前仍验证最终树。新增共享/SPSC测试在时钟回调内制造循环，确认返回`CyclicValue`且不占slot；修复后完整JSON正确写出。

borrowed和owned child logger保留原context合并路径：parent < child < event，已有key保留位置并以新值覆盖。未知输入类型、65字段、cycle/depth/nodes/重复key仍在capture失败，正常emit不分配堆内存；capture失败结束admission且不读取timestamp、不预留queue。

## 验证

`zig build test-capture -Doptimize=ReleaseSafe -j1`包含7项公共API测试：0/5/10字段、optional/bytes/float/128位整数、真实命名struct的64/65边界、动态tuple/slice重复、共享/SPSC源覆写快照、context位置/优先级、初始化后零分配、invalid nested输入与捕获后clock突变。字段模块另有计数测试，命名key不再产生内部key比较、静态scalar不经dynamic派发；组合节点预算与多错误优先级仍和原路径一致。

`zig build bench-capture -Doptimize=ReleaseFast -- --iterations=10000 --repetitions=5`分别报告公开appendFields和完整同步JSON。空append是无工作基线；同步测量包含字段、filter、encoding、sink和written确认，不是journal producer延迟。每批一对时钟，完整JSON由hash消费，borrowed-overwrite作为对照。

before使用独立冻结源码模块，同一benchmark源码将session固定为1，因此before/after可逐行匹配完整JSON字节。45对报告的checksum、输出字节、accepted/written、输入shape、iteration和预算完全相同，测量期Runtime分配为零。原始结果与源码/binarySHA256位于 `bench/evidence/2026-10-31-direct-capture/`。

固定CPU的5次试验中，中位数ns/call如下：

| 操作 | 5字段before/after | 10字段before/after |
| --- | ---: | ---: |
| appendFields，包含key/value hash消费 | 53.43 / 25.42 | 174.54 / 48.71 |
| 无context完整同步JSON | 581.91 / 520.12 | 955.09 / 756.27 |
| borrowed覆盖完整同步JSON | 617.57 / 563.16 | 981.29 / 845.51 |

10字段append候选有较大波动，不能按单一中位数声称稳定提升。完整同步数据仅证明该输入和平台的窄范围结果；不推导任意payload/线程数性能。另一个真实memory-SPSC基准before/after各10次试验，完整交付各50,000条、pending/drop/分配为零，但整体回归工具为inconclusive，队列/调度噪声超过阈值。异步没有稳定速度提升或行业排名的结论。

当前static scalar实验的完整文件user PMU区分标量捕获与64位有界长度统计：仅标量捕获SPSC P4/shared P1指令中位下降2.68%/2.97%，两者组合下降3.00%/3.32%，计数spread均通过门限。正式100项文件试验核对1010万条JSON，吞吐全部inconclusive，多个中位下降。SPSC p50降低但p99有负向中位，额外20项长sampled也观察到该变化；所有原值保留，不宣称低尾延迟或跨库排名改善。完整源码/格式/资源与限制见`bench/evidence/2026-11-01-static-scalar/`。
