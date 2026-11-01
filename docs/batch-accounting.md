# 批内持久化决策和written统计

后台处理一批记录时，配置组已经由受保护的View保持不可变。现在每组预先计算required且reclaim_after=durable的route位图，记录用route_mask与该位图判断确认边界。这个结果只在当前批次使用，不改变配置发布、文件格式或具体sync调用。

任意required route要求durable时，仍将该事件的完整route_mask纳入原有durable barrier，确认该事件选择的全部required目标。best_effort route不会单独改变journal的确认边界；它的写入/flush/sync行为继续由交付管线处理。记录的确认边界存入固定64条数组，不在回收时重新扫描route。

完成计数按连续channel聚合：journal.releaseAfter和配置record pin释放都成功后，才把这条记录加入临时计数。换channel时提交上一段；批次完成和发布progress之前提交剩余计数；错误退出通过defer提交已经确认的前缀。最终原子更新仍使用fetchAdd，因此同步/fallback路径并发增加同一计数器时不会丢计数。相同channel的31条完整批次由31次written RMW减少为1次。

## 确认与观测边界

journal仍逐条执行完整CRC检查、顺序校验和written/durable reclaim。每个槽位的释放、水位、schema引用和恢复协议保持原来实现，未引入批量journal回收接口。批次只聚合计数，不能将后续失败的记录计入成功前缀。

并发health是分别读取各原子值的观测，不是事务快照。written计数可以在批内短暂落后于journal水位，批次结束前会更新；错误返回也保留实际已确认计数。显式flush/shutdown仍是确认接口：它们获取原来的delivery锁，返回前能观察到已完成批次计数，不能通过“health队列为空”替代barrier。

这项修改增加一个consumer栈上的计数对象，不分配堆内存，不增加producer计数步骤。批次配置组增加一个u64派生位图，原记录route_mask数组被较小的确认边界数组替代。所有资源仍由原Runtime拥有，临时统计对象不得跨批次逃逸。

## 验证内容

- 1024种route mask覆盖required/best_effort、written/durable、第64个route位与混合目标，逐项和原扫描方法比较，同时核对完整barrier mask。
- 连续channel变化、空flush、重复flush、其他owner插入更新均精确计数；真实并发测试确认批次统计与同步计数器合成41000次更新。
- 实际shared/SPSC的31条同批记录只发布一次written统计；旧实现会被计数回归以31次RMW拒绝。
- 在三条输出均完成后，故意损坏第二条待回收记录，验证written=1、pending=2、journal水位仅越过成功前缀，剩余记录pin不释放。
- 原混合配置sink失败、View释放、lease保留、deadline及跨进程恢复测试继续执行。

当前源码的Debug和ReleaseSafe定向测试均13/13通过，包括导入fixture及6项实质测试。完整ReleaseFast `verify-local`通过76/76构建步骤、478/478 Zig测试，包含真实SIGKILL、配置事务、独立包消费和Linux原生宿主自校验。最终ReleaseSafe门禁通过22/22构建步骤：九个目标实际生成公共路径对象，配置、事务、deadline和真实文件故障37/37通过。精确源码身份记录在 [qualification.json](../bench/evidence/2026-11-01-batch-accounting/qualification.json)；此前配置View复用的474项历史计数不作为本轮证据。其他四平台的设备运行资格仍未取得。

完整JSON文件before/after对照保持字段、系统时间戳、Memory/Mmap、shared/SPSC、prepared形状、队列和文件buffer预算，并包含最终written flush、shutdown和对象清理。原始记录与构建身份见 `bench/evidence/2026-11-01-batch-accounting/`。减少原子操作和route扫描次数不自动等于所有工作负载更快。

## 完整流程测量

5种配置各以batch和sampled模式在独立进程运行5对before/after，共100次试验。每次100000条测量记录和1000条预热，逐条验证1010万条完整JSON日志，包括字段、消息、时间戳、scope、事件身份与计数；同时保存输出文件SHA256和物理字节数。应用和kron模块均为ReleaseFast、保留frame pointer，固定CPU0/2/4/6/8/10，交替before/after顺序。before是配置View复用已经完成、尚未加入本轮统计聚合与durable mask的冻结源码。

| batch模式 | before中位条/秒 | after中位条/秒 | 中位变化 | 本轮判断 |
| --- | ---: | ---: | ---: | --- |
| shared Memory P1 | 1,272,767 | 1,252,057 | −1.63% | inconclusive，after跨轮spread约31.2% |
| shared Memory P4 | 1,221,402 | 1,226,962 | +0.46% | inconclusive，before跨轮spread约19.4% |
| SPSC Memory P4 | 1,192,114 | 1,173,534 | −1.56% | inconclusive，after跨轮spread约14.6% |
| SPSC Mmap P4 | 1,220,463 | 1,205,500 | −1.23% | 通过本机噪声阈值，置信区间仍重叠 |
| SPSC Mmap P4 prepared | 1,230,803 | 1,273,351 | +3.46% | 通过本机噪声阈值，置信区间仍重叠 |

`stable_local_measurement`只表示before/after的CV和相对spread均低于10%，不是统计显著或跨平台收益。最后两组中位吞吐的trial bootstrap 95%区间分别仍重叠；本轮不宣称稳定端到端提速，保留普通Mmap的下降及所有慢值。sampled模式大多数producer分位数仍inconclusive；prepared的p50中位493→501ns、p99为16591→16538ns，不能据此宣称tail改善。完整指标见 [comparison.json](../bench/evidence/2026-11-01-batch-accounting/comparison.json)。

这批试验的完成边界是written文件flush、shutdown和对象清理。durable route预计算另由1024种mask与原扫描oracle验证，不能把本次written吞吐当作fsync性能。与Quill/Foundation的既有数字使用较早源码，累计优化后的跨库排名仍须同轮复测。
