# Runtime线程状态按预算分配

**候选已撤回，生产代码恢复e40313f。** 明确的15KiB空间收益未取得shared P1吞吐无代价的资格。新增requested-resource基准与证据保留，SPSC仍是高级可选，当前Runtime状态布局保持原实现。

普通应用优先shared Memory/Mmap，SPSC保留为固定线程的高级可选路径。Foundation的Memory与单Mmap同样使用共享队列，没有SPSC模式；当前本地config/backend与两个queue的拥有源码hash见foundation-shared-source.json。本轮只比较kron资源修改前后，不提供新的跨库排名。

基线是`e40313fc9d5e012140ad00788492763d7bd8ce5a`。完整流程before二进制来自`fd4e941`；`git diff fd4e941 e40313f -- src bench/cpp_reference/kron_reference.zig`为空，二者生产代码与基准相同。before/after二进制SHA256见各provenance.json，全部src及两个基准的candidate源文件身份见after-provenance.json。`baseline-src.tar.xz`与`candidate.tar.xz`冻结拥有源码；候选快照不含随后新增的build step，生产代码未再改动。机器、CPU拓扑、governor和源码归档身份见environment.json。

## 实现与空间

原Runtime内嵌64份Counters（每份192B），另分配64份配置缓存（每份48B），无论是否允许thread attachment。实验候选按`max_thread_channels`一次预分配ThreadState：counter和cache共同保持稳定地址，普通0预算使用空slice。channel detach和destroy继续释放配置pin；状态块在配置manager之后释放，初始化错误按相反所有权顺序回滚。每条事件、filter reload、flush和detach不新增分配；queue、record格式、CRC、恢复和交付协议保持。

70次resource trial覆盖7配置、各5对。以下是所有重复中相同的Runtime allocator请求的live heap空间；不是RSS，也不包含其allocator以外的native I/O、线程、OS mapping或完整Logging所有输出。

| 模式 / channel预算 | before B | after B | 节省 B | 初始化分配 before→after |
| --- | ---: | ---: | ---: | ---: |
| sync / 0 | 461568 | 446208 | 15360 | 11→10 |
| shared Memory / 0 | 471168 | 455808 | 15360 | 15→14 |
| Memory / 1 | 481208 | 466104 | 15104 | 23→23 |
| Memory / 4 | 511088 | 496752 | 14336 | 38→38 |
| Memory / 64 | 1108688 | 1109712 | −1024 | 338→338 |
| shared Mmap / 0 | 462464 | 447104 | 15360 | 14→13 |
| Mmap / 4 | 467568 | 453232 | 14336 | 45→45 |

Runtime owner的`@sizeOf`为12800→512B。ThreadState因Counters的64B对齐为256B；64-channel上限因此比原counter/cache组合多1KiB。这是普通和低预算配置减少空间的取舍，不宣称所有配置都减少内存。queue/journal reservation在所有配对中保持一致。resource probe实际完成一次written、关闭并验证全部请求空间释放；初始化墙钟有宿主I/O噪声，不作为稳定启动加速的证据。原始数值在resources.jsonl、resource-comparison.json，resource-binaries.json保存二进制身份。`reported_thread_state_bytes`的before只含内嵌counter数组，不含独立cache；总请求空间已包含二者。

新增resources.py驱动另执行70项，全部配置的live bytes、allocation count、owner size与reservation完全复现原值；新报告在resources-script-check.jsonl及resources-script-check-comparison.json，初始化耗时不参与确定性判定。

## 完整输出验证与资格

正式主路径使用`--frontend=managed`的Logging入口、shared Memory/Mmap、P1/P4、batch/sampled，各5对，30万计时事件和1000 warmup。portable真实文件、完整系统timestamp与元数据、5个数值字段、256槽/512B、64KiB文件buffer、每队列4量子。计时终点包含捕获、入队、消费者编码、实际written、shutdown及destroy/cleanup；另列init、preparation和完整lifecycle。没有durable flush。CPU固定0/2/4/6/8/10（六个物理core各一个逻辑CPU）。每次前后校验candidate源码与二进制hash，独立oracle逐条核对实际文件内容、顺序、metadata、accepted/written/pending/drop和资源。

先前200次标准矩阵的命令漏传`--frontend=managed`，实际全是直接Runtime入口。原workflow-comparison.json的scope写成managed是错误标注，应以每条原始row.frontend及本说明为准；最早试验还和resource build step编译重叠，因此作为pilot保留，不据此接受或否决性能。发现入口错误后启动的第一份shared-repeat同样实际使用Runtime，被主动中断；所有已验证row与log原样保留，不拼接到正式managed结果。当前measure.py明确传frontend参数并验证row.frontend，默认managed，可显式`--frontend=runtime`复现原入口。

正式80项逐条核对2408万条JSON；另20项P1 batch复测核对602万条JSON。下表为written到cleanup完整吞吐，单位M条/s；每个数值为5次的中位数，不删除慢值。

| shared配置 | before | candidate | 变化 | 本轮资格 |
| --- | ---: | ---: | ---: | --- |
| Memory P1 batch | 2.320 | 2.132 | −8.10% | 波动超门限，区间重叠 |
| Memory P1 sampled | 2.177 | 2.244 | +3.09% | 波动超门限，区间重叠 |
| Memory P4 batch | 2.194 | 2.163 | −1.40% | CV/spread达标，区间重叠 |
| Memory P4 sampled | 2.136 | 2.125 | −0.48% | 波动超门限，区间重叠 |
| Mmap P1 batch | 2.304 | 2.073 | −10.02% | CV/spread达标，区间不重叠 |
| Mmap P1 sampled | 2.180 | 2.230 | +2.28% | 波动超门限，区间重叠 |
| Mmap P4 batch | 2.167 | 2.182 | +0.67% | 波动超门限，区间重叠 |
| Mmap P4 sampled | 2.207 | 2.172 | −1.60% | CV/spread达标，区间重叠 |
| Memory P1 batch复测 | 2.337 | 2.225 | −4.80% | CV/spread达标，区间重叠 |
| Mmap P1 batch复测 | 2.260 | 2.243 | −0.76% | CV/spread达标，区间重叠 |

P1 batch初轮10个配对速度比全部低于1；复测未重现Mmap约10%的显著负向，但Memory中位继续负向。不能将这些数据当作稳定因果归因，也没有足够证据证明空间优化对主路径无代价，因此保守撤回。结构布局probe记录Runtime和Counters的实际offset/size/alignment：Zig自动布局同时重排了控制字段，尚未独立隔离cache sharing或锁等待，不将回退直接归因于某一字段或parking_lot。

全部慢值、初始化/关闭/清理阶段、中位数、CV/spread、bootstrap区间见shared-managed-repeat-results.jsonl、shared-managed-repeat-comparison.json、shared-p1-batch-results.jsonl及shared-p1-batch-comparison.json。宿主load在首轮约86.6–87.5，affinity不等于独占CPU。被主动中断的Runtime shared-repeat保存12个已验证trial、361.2万条JSON；pilot、正式与复测分别报告，不拼接为一轮稳定性能资格。局部资源节省不叠加到先前Foundation+spdlog/tracing数字，不通过中位数变化宣布整体超越。

## 验证与复现

实验候选的Debug管理/outputs/transactions 51/51通过。新线程状态定向测试Debug与ReleaseSafe各17/17（包含导入fixtures），普通sync/Memory/Mmap默认零状态、禁止后续分配时emit/filter reload/flush/关闭、1/4/64预算全部channel的稳定地址和pin/counter、exhaustive allocation-failure rollback均通过。候选ReleaseSafe完整门禁151/151步骤，641项通过、1项无libc系统local能力skip；包括九目标对象、独立源码分发、真实SIGKILL/恢复及示例。非Linux对象不替代设备运行。这些计数属于归档candidate，不作为撤回后HEAD的测试计数。原始gate日志在本目录。

撤回后`git diff HEAD -- src`为空，生产源码恢复基线。当前Logging/独立outputs ReleaseFast为6/6步骤、43/43测试通过；当前独立源码分发ReleaseSafe为2/2步骤通过，五模式各2条实际JSON均核对。新增bench-runtime-resources的当前ReleaseFast入口成功运行，默认Memory返回原12800B owner/471168B请求空间、1条written并释放全部分配。相关post-revert日志独立保存；decision.json记录源码恢复、各捕获数量、原scope纠正与采纳决策。

```sh
zig build bench-runtime-resources -Doptimize=ReleaseFast -- memory /tmp/existing-directory 0
python3 bench/evidence/2026-11-02-thread-state-budget/resources.py \
  --before .zig-cache/runtime-resources-before \
  --after .zig-cache/runtime-resources-after --capture-name resources-repeat
python3 bench/evidence/2026-11-02-thread-state-budget/measure.py \
  --shared --frontend=managed --capture-name shared-managed-repeat-2
```

脚本不覆盖已有捕获。完整流程脚本使用provenance指定的冻结二进制并检查身份；运行前须在独立实验checkout恢复candidate归档的源文件，live source guard会拒绝已经撤回的HEAD。resources.py接受显式冻结二进制，每次校验其hash并将命令/身份写入新报告。源码归档可用于重建：从candidate提取bench文件和src，从baseline-src提取另一份src；根模块与kron依赖均选择ReleaseFast。fresh build二进制因源码路径等原因可能具有新hash，应记录新的provenance后单独捕获，不能冒充原测量身份。定向测试和生产diff保存在candidate.tar.xz、rejected-candidate.patch；布局probe的首个format编译错误也保留在runtime-layout-probe-error.log。
