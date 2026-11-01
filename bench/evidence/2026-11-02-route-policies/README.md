# 输出默认值与route策略

Logging.Options新增defaults与capture分层，各Route覆盖format/timestamp/filter/min_level/sampling/sample_bypass/redaction/predicate/delivery/reclaim_after/输出上限。提交模式、queue、线程、总预算和consumer scratch是实例资源，文件buffer/backend是target资源。旧平面参数继续兼容；全局redaction/predicate保持捕获前语义。

## 功能与验证

- route采样在字段捕获前计算实际mask，所有route拒绝时lazy provider不执行；显式route独立预算由所有producer共享。默认继承策略保留共享sampler，filter-only不重置，full replacement新状态。
- 输出redaction只改变本route的attributes/deferred嵌套渲染，capture.redaction和Secret在队列前保护；被其他route使用的原值可存在queue，输出脱敏不冒充捕获安全。
- timestamp/predicate可以显式关闭继承，redaction空数组和sampling.none是明确覆盖。
- 每route编码上限<=实例scratch，required超限报错保留record，best_effort跳过且报告错误，未输出合法前缀冒充成功。
- route策略由不可变配置版本拥有，旧记录按旧规则交付；输出redaction/limit进入恢复fingerprint，采样相位不进入（mask已固定）。

11项公共集成覆盖sync/shared/SPSC Memory/Mmap、独立采样/脱敏/日期、四producer精确配额、lazy、nested/deferred、prepared与配置替换、Mmap恢复拒绝/原策略重放、OOM与不截断原文件。Debug/Safe/Fast通过，原配置/事务/filter/predicate28项通过；独立包和single-threaded消费另有route API验证。最终完整gate与平台结果记录在qualification.json。

新例子 `zig build run-route-policies` 写required JSON文件与stdout text：文件4条password drop，stdout选0/2并mask，捕获access_token全部mask，local/source路径一致。指南见 [usage](../../../docs/usage.md#接口与默认配置)。

## 默认路径完整比较

两个外部ReleaseFast/native二进制使用相同系统时钟、五字段完整JSON、P1/P4、shared/SPSC、Memory/Mmap、256槽/512B载荷、64KiBportable文件、block与consumer budget4，sampled/batch各五次交替，共160项/1616万条物理JSON核对。默认未配置route策略不创建Policy/Redactor，新增route指针与snapshot mask的空间成本在qualification中说明。

batch完整关闭时间中位变化约-2.5%到+3.6%，各组均因CV/spread超10%或区间重叠保持inconclusive；完整输出hash、预算、accepted/written和阶段严格核对。此测量没有证明任意负载零开销或新的跨库优势，全部负向/慢值保留。

`results.jsonl`、`comparison.json` 和`identity.json`绑定被测二进制。最终source archive/hash单列：被测候选构建之后补充了冷校验和输出策略fingerprint规则，没有对那些可选路径作性能收益声明。输出redaction会增加自己的树复制和渲染成本，默认无该规则不使用大scratch。

## 独立候选边界

此前有界并行Mmap初始化实验已被否决并恢复：640项/6464万条对照未获得稳定初始化优势且有可重复p99.9负向。其全部源码/数据/分析失败与否决理由位于 [初始化实验](../2026-11-02-parallel-mmap-initialization/README.md)，不用于解释本功能的排名。
