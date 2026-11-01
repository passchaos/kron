# 有界并行Mmap初始化候选：未推广

基线与候选源码归档、二进制身份、完整数据在qualification.json、manifest.json及baseline/candidate-source.tar。候选只将Linux多channel的SPSC文件创建分成最多四个冷任务，使用稳定allocator gate串行访问调用方allocator；每个channel仍完成原文件/目录同步并retire，返回前join全部任务，失败释放当批和此前成功channel。Memory/单channel及其他平台保持串行。

## 决策

640项完整文件对照核对6464万条JSON，另16项smoke核对161600条。部分SPSC Mmap初始化中位下降，但各初始化组均未通过重复性门限，bootstrap中位区间重叠。多个完整吞吐中位负向，其中P4 inline/512B sampled的p99.9由347303→366141ns（+5.42%），重复性通过且中位区间不重叠。额外冷线程、allocator gate及对象状态未取得稳定整体收益，候选已撤回生产。

## 正确性与资源

Safe相关20/20、Debug/Fast19/19；实际文件发布重叠握手、晚期同步失败join/全部文件锁释放、Memory串行无gate、原OOM全扫描/错误线程/附着复用通过。单线程/并发集成6步骤、13项通过。未为否决候选声明完整门禁或设备资格。

候选并行宽度4、每worker申请256KiB栈，Registry增加8B指针并仅多channel Mmap增加1个gate分配；通道backing/record预算、CRC/预热/发布与written/durable协议保持。平台页探针确认可写预热会把整段共享映射标脏，因此仅缩小memset不能消除主要发布成本，没有用只读预热转移producer缺页来宣称等价优化。

## 测量与限制

相同系统时间、完整五字段JSON、portable、block、256槽、P1/P4、shared/SPSC、Memory/Mmap、inline/schema、512B/8192B载荷预算、sampled/batch、五次交替before/after，共640项。包括init、preparation、producer、written flush、shutdown、cleanup，逐条物理JSON由既有独立oracle核对。数据包含全部负向与慢值，不比较Foundation，也不做新的durable测量。

最初summary代码用tuple/list case比较导致分析阶段失败，所有640条测量已成功完成并核验。修正归一化后从同一原始行生成comparison.json，没有重跑/筛选trial；原分析失败日志保留。comparison driver的负向测试验证预算/后端漂移、缺失重复和tuple/list分组。

后续输出route策略与实例资源分层是独立功能，不以此否决候选数据宣传性能收益。当前完整目标差距见 [验收页](../../../docs/implementation-status.md)。
