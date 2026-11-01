# Managed owner传递和入场帧优化

基线58a9a9b提供独立outputs管线。当前改动借用内部Owner和Frontend辅助调用，去掉始终全选的重复mask，并将单输出的入场状态和多输出批量状态分开；public emit/log方法仍按值保存本次scope/context/trace。配置、队列格式、采样、脱敏、CRC、prepared和完成边界保持原语义。

x86_64 ReleaseFast对象布局中，旧Frame为2320B、8帧18560B；新Frame56B、8帧448B，多输出Fanout另保留18496B。总TLS比旧结构增加384B，优化针对单输出访问的热状态，不是减少全部TLS或省略多输出预算。

新增两项有实际边界的测试：lazy provider修改caller scope/trace时，本事件保留原值；单/双输出混合嵌套8层、拒绝第9层后，全部admission释放且每个owner可再次提交。原64输出、partial success、错误归属、thread/prepared、scope/token、deadline和无分配用例继续执行。

ReleaseSafe完整门禁151/151步骤成功、638项通过/1项无libc系统local能力skip；九目标对象、源码分发、实际崩溃、错误/lease、19示例、Python oracle通过。ReleaseFast管理输出/capture/route策略61/61，调用快照定向14/14含导入fixture。原始日志在本目录。

同源managed_outputs.zig覆盖1/2个真实文件、sync/Memory/Mmap/SPSC，单producer，20k计时事件+1k排空warmup，256槽/8192B、portable、written shutdown。总完成包含捕获、提交、消费者JSON编码、实际文件和关闭；初始化单列。对照脚本校验每个文件的全部JSON、id/payload/sequence/config_generation/session。二进制及source hash、全部慢值和区间保留。

正式数据按single/double及独立repeat分目录；结果不代表Foundation排名。当前跨库实际对照另见 [两个Foundation前端](../../cpp_reference/evidence/2026-11-02-managed-frontends/detailed-comparison.md)。

## 结果

两次独立对照共480 trial、1512万条实际JSON全部核对。下表为配对完成吞吐的中位变化；完整区间在各comparison.json。

| 模式 | 单输出第一轮 / 重复 | 双输出第一轮 / 重复 |
| --- | ---: | ---: |
| sync | +1.09% / +1.07% | -0.87% / -0.93% |
| memory | +3.75% / +2.92% | +1.25% / +2.16% |
| mmap | +2.12% / +2.24% | -0.27% / +1.14% |
| spsc_memory | +5.61% / +3.57% | +5.70% / +3.85% |
| spsc_mmap | +2.46% / +3.99% | +1.65% / +4.02% |

单输出Memory、SPSC Memory/Mmap的两轮95%区间均在1以上；共享Mmap首轮区间跨1、重复改善，sync重复区间跨1。双输出Memory/SPSC Memory两轮改善；Mmap类首轮部分区间跨1，sync均inconclusive。没有把这些局部before/after变化叠加到跨库数字。宿主load较高，CPU affinity固定为0/1（同一物理core的两个逻辑CPU），说明与跨库六物理core窗口分别保留；不能混为同一负载。
