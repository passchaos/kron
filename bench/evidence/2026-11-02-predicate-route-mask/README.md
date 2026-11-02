# 不可变route predicate掩码

每个Selection新增一个`u64 predicates`，配置发布时从精确route table构造，包括显式filter分支和最高位63。submit在global predicate之后仅遍历`event.route_mask & predicates`，保持原route索引顺序、旧snapshot资源、完整树验证和错误先后。无predicate默认路径跳过route扫描；未选中route的regex继续不执行。wire/CRC/schema/recovery fingerprint不变。

独立Selection扫描测试覆盖0/1/63/64 routes、inherited/explicit filters、selected交集、旧Selection不变与presence/expression replacement重建。根筛选首次只执行导入检查，不算模块完成；实际组合过滤15/15通过，日志明确有Selection目标test。Public predicate/transactions Safe15/15通过；新增sync/async 64route最高位测试确认未选regex的InputTooLong不会提前出现，输出route_mask保持1或9223372036854775809，predicate gate8/8通过。

只改变Selection/Runtime的冻结副本以当前full文件流程做E-core40项PMU，核对4,040,000条JSON，P1/P4 Memory/Mmap用户态instructions约减少0.16%，三组取得局部门限、一组不确定；cycles与完整吞吐正负混合，全部不确定。P-core Memory P1百万条10项独立核对10,010,000条JSON，配对中位0.982、区间0.863..1.004，inconclusive；不称为稳定收益或回退。源码在`predicate.patch`，原输出、CSV、窗口与二进制hash在`ecore-pmu/`和`pcore-p1-long/`。

该机制随后与JSON member直接前缀组合验证。组合与单独的百分比不叠加，默认一条route减少的小量CPU工作不能外推为全面性能胜出。最终保留范围与完整门禁由[JSON前缀证据](../2026-11-02-json-member-direct/README.md)跟踪。
