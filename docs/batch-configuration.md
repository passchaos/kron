# 后台批次的配置复用

后台从一个journal取出最多64条记录后，对该批次中的每个配置版本持有一个受保护的View。相同generation与fingerprint的后续记录复用这个View，不再逐条扫描配置表、增加并减少reader计数。这个做法借鉴Quill和Foundation将消费端重复操作合并到批次的方向；journal的commit、CRC、顺序和输出确认边界保持不变。

临时批次对象位于consumer栈上，容量固定为64组，不分配堆内存。记录解码后仍核对完整配置身份与route_mask，按原route、format和sink交付；各组累积route mask，执行相同written/durable barrier。旧View在整批交付、barrier和record reclaim完成后才释放。错误路径也通过defer释放批次View，但不撤销未确认记录的pending pin，不触发资源lease提前释放。

当前Runtime捕获的记录有明确非零route generation。历史记录的generation=0则每次重新执行Manager.find的完整指纹/歧义校验，再复用已经解析出的相同snapshot；不会以第一个命中替代历史恢复身份验证。filter-only reload和full replacement的发布方式不变，缓存只存在于当前批次，不保留跨批次的裸指针。

每条record仍独立确认，所有原CRC校验继续执行；这轮配置View复用没有引入批量回收API或改变accepted/written/durable协议。后续已单独加入durable route位图预计算和连续channel的written统计聚合，验证与测量见 [批内确认与统计](batch-accounting.md)。journal游标与reclaim仍逐条处理，不能把快照复用称为已完成全部批处理。

## 验证

模块测试直接核对真实Manager.find调用次数：同一版本64次选择只有一次查找；64个不同generation各查找一次，即使目标指纹相同也保持独立View。持有View时旧版本不能collect，批次结束后可回收并仅释放一次lease。错误指纹/未知generation继续报错；历史generation=0每次重新查找且复用不分配。

真实后台测试用reservation gap预先建立31条完整事件，再开放consumer，核对共享与SPSC队列在31次sink回调间没有额外find调用。另一个混合版本测试在新sink失败时核对旧输出前缀、全部6个journal record保留、written为0、两个版本无临时reader泄漏，record pin与lease均保留。原配置事务、资源热替换、deadline与跨进程恢复测试继续执行。

完整流程before/after使用同一JSON布局、系统墙钟、512-byte journal载荷预算、256槽队列、64KiB文件buffer、written flush与shutdown/清理。比较包含shared/SPSC、Memory/Mmap和prepared schema，固定CPU affinity并交替试验顺序。原始报告与源码/二进制身份见 `bench/evidence/2026-11-01-batch-configuration/`；局部查找次数下降不能直接换算为端到端日志吞吐。

## 完整流程测量

5个配置、sampled/batch两种独立进程，各5对before/after，共100个试验。每个试验100000条测量记录和1000条预热，逐条解析核对1010万条完整日志。应用与库均以ReleaseFast构建并保留frame pointer，固定CPU0/2/4/6/8/10。记录producer时间、最终written flush、shutdown、对象清理及调用分位数；没有省略时间戳、字段或错误检查。

| batch模式 | before中位条/秒 | after中位条/秒 | 本轮资格 |
| --- | ---: | ---: | --- |
| shared Memory P1 | 1,156,635 | 1,259,012 | 本机约8.9%提升，跨轮spread均低于10% |
| shared Memory P4 | 1,112,450 | 1,138,738 | inconclusive |
| SPSC Memory P4 | 1,098,274 | 1,205,207 | inconclusive |
| SPSC Mmap P4 | 1,143,207 | 1,165,445 | inconclusive |
| SPSC Mmap P4 prepared | 1,194,094 | 1,159,759 | inconclusive |

这是本次开发宿主的同条件结果，不代表所有工作负载或平台。prepared场景没有观察到收益，较高producer速度也会改变backpressure与后台批次大小；不能把各阶段中位数相减解释为每条日志的独立成本。全部min/max、分位数和慢值保留于comparison.json。既有跨库对照使用不同构建快照，应在累计优化后重新同轮运行。
