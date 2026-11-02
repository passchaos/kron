# Shared admission固定分片：候选撤回

本轮实现了64个独占64B cacheline的shared入场计数，经过确定性并发回归和双拓扑完整文件验证后撤回。生产继续原单word flags/count协议。保留独立的最后入场调用唤醒回归，明确两个Foundation前端的超越目标仍未完成。

## 实现与正确性边界

候选基于`1bc811f`，global word只保存cut/closing/revision；OS Thread.Id哈希到64个片，TLS保存本次片token。片count CAS前后SC读取global revision，跨cut的临时获取准确回退；所有片冻结且归零后才snapshot reservation targets。关闭冻结shared/config/SPSC入场后才发布collector退出点；资源/view释放在原token递减之前，临时获取的closing回退也notify worker。revision耗尽永久关闭而不回绕。公共Logger、CRC、journal、配置与SPSC协议保持原边界。

精确源码在`candidate-source.tar.xz`、`candidate/src/`、`candidate.patch`与`provenance.json`；冻结基线源码在`before-source.tar.xz`。所有后续测量使用冻结二进制，生产恢复不改变其身份。

模块确定性回归13项在Debug/Safe/Fast通过：global初读后暂停、CAS后复查前暂停、成功持token未reserve、同片/跨片、closing与endCut两种顺序、wake先于futex wait、临时获取回退零值先于globalclosing发布，以及revision耗尽。Runtime最终无记录admission唤醒和revision耗尽各优化级别通过。ReleaseSafe公共integration/deadline/logging/single-threaded共12/12步骤、53/53测试通过；计数包含引入模块的匿名测试，不称为唯一测试数。相关日志保留。

## 完整流程

默认CRC，public managed async、Memory/Mmap、P1/P4、batch/sampled、256槽/512B、五数值typed fields、系统墙钟、64KiB portable file，written flush→shutdown→cleanup。E-core和P-core各80项100k+1k试验，再做P-core 80项300k+1k长流程；各完成物理JSON oracle，没有pending/drop。

| 100k batch配对after/before | Memory P1 | Memory P4 | Mmap P1 | Mmap P4 |
| --- | ---: | ---: | ---: | ---: |
| E-core | 1.009 | 1.000 | 1.005 | 1.013 |
| P-core | 1.018 | 0.953 | 1.088 | 0.994 |
| P-core 300k | 0.946 | 1.004 | 1.027 | 1.004 |

E-core吞吐全部inconclusive，Mmap P4 sampled的p99取得局部负向资格（before/after速度比约0.957，after耗时约+4.5%）。P-core 100k Memory P4 batch取得局部负向资格，长流程没有重现同一P4负向，但全部吞吐仍不确定，并出现Memory P1 batch −5.4%和Mmap P4 sampled −3.6%的配对中位。不能挑长流程P4中位约持平忽略其余慢值。

两种拓扑独立记录：E-core CPU16/18/20/22/24/26，P-core CPU0/2/4/6/8/10。所有配对轮次、区间、两侧spread、尾部和init/lifecycle在各目录`results.jsonl`/`summary.json`，高噪声保留inconclusive。

## CPU和资源

额外E-core 40项100k完整文件PMU核对4,040,000条JSON。P4 Memory/Mmap用户态cycles配对速度比1.107×/1.121×，达到本轮局部下降门限；P1 cycles不确定。instructions中位约增加0.13%–0.20%，Memory P1取得轻微负向资格。CPU成本下降没有证明完整吞吐或尾部改善，不推导跨库排名。

五模式资源探针（sync、Memory/Mmap×thread budget0/4）各before/after完成emit/flush/shutdown且初始化后FailingAllocator未触发。Runtime owner从12800B增至16896B，每模式live requested bytes增4096B；分配次数和队列/journal预算保持。Runtime allocator全部释放。此计数不包含OS mapping/I/O内部allocator；TLS frame另增加一个token指针。数据在`resources.json`。

总共280项完整文件/PMU试验，核对44,280,000条JSON。候选没有获得完整性能资格且有资源/尾部/吞吐负向，全部撤回。`src/core/tests/runtime_admission_shutdown.zig`保留基于现生产协议的futex握手：消费者在closing且只有一个入场调用时实际进入等待，最后调用不提交记录直接end，shutdown仍完成；ReleaseSafe筛选通过15项含导入测试，日志在`retained-wakeup-safe.log`。它验证最终唤醒，不表示分片方案保留。

下一候选转向CRC四lane的并行等价合并，保留原IEEE常数域、三处校验、header/reference/payload分段和短tail。共享分片实验的cycles收益与新CRC实验不能叠加成当前性能百分比。

```sh
python3 bench/cpp_reference/compare_versions.py --before BEFORE --after AFTER \
  --output-dir FRESH --affinity 16,18,20,22,24,26 --events 100000 --repeats 5
zig build test-integration test-deadline test-logging test-single-threaded \
  -Doptimize=ReleaseSafe -j1 --summary all
zig test src/root.zig -O ReleaseSafe --test-filter 'shared runtime final admission'
```
