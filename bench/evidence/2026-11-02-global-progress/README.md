# 全局进度等待者登记实验：已否决

基线fd4e941。候选为共享producer与written control登记等待者，SC顺序发布epoch，在无人登记时跳过全局futexWake；SPSC本队列space协议、四量子服务预算和记录/输出/回收边界保持。测试源码和完整生产候选保存在candidate.tar.xz，生产代码已恢复基线。

诊断24项/242.4万条实际JSON核对，SPSC全局唤醒调用从约414–425降至4–8，共享队列从约1586–1618降至804–827。该观察是带IO包装的操作计数，不作为完整速度或真实睡眠次数。

定向Debug/ReleaseSafe/ReleaseFast各23/23（含导入fixture）；覆盖多共享producer登记、通知发生在登记前/登记后但真实futex调用前、epoch回绕、written control、worker错误、SPSC本队列行为和无人等待时跳过广播。相关公共ReleaseSafe74/74，完整日志保留。

无插桩完整工作流200试验/2020万JSON：shared/SPSC、Memory/Mmap、P1/P4、batch/sample、inline与两个prepared控制。多数结果inconclusive，shared sampled部分负向；SPSC Mmap P4 batch负向12.41%且高波动，全部慢值保留。

按用户最新偏好，独立复测只聚焦shared Memory/Mmap，300k事件+1k预热、P1/P4，80试验/2408万JSON。Memory batch中位P1/P4分别−1.02%/−2.91%，重复性门限内但bootstrap区间重叠；Mmap和sampled组也互有正负，尾分位仍inconclusive。降低广播次数没有证明共享路径整体收益，候选全量否决，没有把低p99或较少wake调用当作整体优化。

常规接入继续优先shared Memory/Mmap，SPSC保留为需应用验证收益的高级能力。Foundation仅共享Memory与单Mmap。后续优化转向普通模式资源/核心路径成本，不推广未确认收益的SPSC调度或此候选。

所有actual output/count/backend/resource与source/binary hash核验通过。baseline-src.tar.xz、candidate.tar.xz、before/after-provenance.json、decision.json及原始每项数据保留；没有media durable或跨库排名结论。

280份逐项stdout/stderr完整保存在trial-logs.tar.xz，每份SHA256在trial-log-sha256.json中，压缩后逐份核验一致。
