# Global progress 等待者登记候选

这是185e700生产算法上的独立候选。此前精确CRC与CASpause各有稳定控制反例，全部拒绝并记录；本轮不继承它们的局部比值。

只增加一个全宽Atomic(u64)通知提示计数与一个privatevoid helper。shared Full/block及flush/cut written等待scope登记和defer退出；SPSC producer继续原queue-local waiting协议，控制线程等待SPSC written目标则属于global等待者。进展通知每次都推进原u32 epoch，再检查SC count，非零沿原wake-all，仅零省wake。计数到UINT64MAX后永久always-wake，两方向不再改变，不增加error/token/TLS/生命周期屏障。

SC次序：通知A(epoch推进)在C(count读)前；等待者R(登记)在原终态检查和futex前，D(退出)在wait返回/错误退出后。R<C<D时count非零或sentinel，保wake；C<R时A<C<R，原epoch与发布状态/futex原子检查保留已有通知观察。多个等待者共享精确count，退出一个不清除其他人的wake提示。原MAXu32→0单次回绕保持；完整2^32周期ABA仍是原协议域，不能用一次wrap测试声称新增无限停顿保障。

workerError仍优先closing；waitForCut初次written条件已满足时保持原直接完成行为，count不提前到函数入口。timed caller timeout/cancel仅detach，控制任务的登记直到实际完成/失败才退出。所有通知来源、requiredflush/checkedreclaim/pin/written顺序、closing/admission/config/workerwake/SPSCepoch、capture-before-clock、原整数/CRC3点/256slot512B预算保持。

新增测试必须覆盖真实Memory/Mmap通知先于/后于登记、多个等待者、错误/closing与timed detach、永久overflow模式，并转发真实futex。先验证完成，再在cleanup失败路径救援wake；不能把救援当通过。已有关闭/cut/pin/flush/SPSC回归也实际执行。

实际source/compiledlayout/Frame/call/resource与双拓扑完整流程资格尚未取得。baseline Runtime12800B align64，最后已用字段12785留15B尾padding；newfield原始8B不代表实际增长为零，自动布局可能移动成员，后续actual检查才能判断cacheline与申请量。当前没有速度或Foundation排名声明。

## 完整流程决定

候选已拒绝。两种拓扑共320项完整managed流程，逐条核验32320000条物理JSON，actualfullmetadata/256slot/512B、accepted/written完整、drop/pending为0。E-core104个轴中26个稳定负向、1个p99局部正向、77个不确定；written16组中9组稳定负向，包括async7/8组约5%–10%退步。P-core104轴中6个稳定负向、98个不确定，其中async Memory/Mmap P4 sampled written速度比分别0.88645/0.93404。完整正负和区间见 [E-core](flow-ecore/summary.json)、[P-core](flow-pcore/summary.json)。比值大于一有利于候选，局部p99正向不覆盖吞吐与其他尾部反例。

原SC/lostwake/overflow/真实futex及生命周期测试通过与性能资格分开。native Debug/Safe/Fast、generic Safe各11个具名case实际通过，初次compilefail与观察边界修正保留。依 [performance-plan.json](performance-plan.json) 未扩展schema或Foundation，生产算法仍185e700；默认CRC3点、原预算、Clock/capture/borrow/pin/barrier均保持。

[actual-review.json](actual-review.json) 记录Runtime仍12800B，但字段重排，counter12480与admissiongate12632不在同line；helper94B真实outline，submitframe+16B、4helpercalls/totalcalls+3，cut4个inlineCAS及stackrefs增加；5个epochRMW都保留，count0只省wake。production无testhookstorage/callback/参数。未采集动态重试或wake次数，不能将完整退步归因于某个静态变化。

[decision.json](decision.json) 保留所有稳定正负、原始source/archive/compiler/binary身份与资格范围。下一独立方向是固定20/24段平坦lookup数学与caller成本验证；不复活此前PCLMUL候选，也不叠加历史速度比。整体Foundation两个前端目标仍未完成。

Runtime全部39个字段的before/candidate实际偏移另见 [runtime-member-offsets.json](runtime-member-offsets.json)，不以总size相同推断字段未移动。
