# 路由过滤与派生掩码

同一个全局scope阈值通常由多个route继承。此前每次enabled或begin都扫描全部route，再检查各route的filter和min_level。现在配置发布时生成各日志级别的继承掩码，以及独立filter的route位图。

调用时仍获取绑定到该配置版本的全局阈值；阈值允许当前level时读取其继承掩码，再遍历独立filter位图。每个独立route按自己的scope规则和min_level决定是否加入结果。level=off始终返回空掩码。独立filter不受全局off限制，scope仍按原来的边界和最长匹配规则处理。

派生数据属于不可变snapshot，在gate发布前生成。filter-only reload不改变route/min_level，因此复用掩码并使用新的全局阈值；full replacement按新route生成掩码。旧版本的pending、reader、channel pin和recovery fingerprint都沿用原协议。每版本额外64字节，无热路径分配、锁或新的原子操作；该数据不进入持久化文件。

## 正确性证据

内部对照测试遍历0/1/2/7/63/64个route、全部7种全局阈值、7种事件level与10种scope，用原逐route扫描计算期望值，共2940种组合。另覆盖全部64位继承掩码、全局off时独立第64个route接受，以及off事件拒绝。

外部 `test-route-filters` 使用实际公开Logger和64个独立sink，在sync、共享内存async、SPSC内存async下检查enabled、emit结果、JSON route_mask和每个sink的交付计数。测试跨filter-only reload与完整route/min_level替换，并检查旧快照保留和channel缓存刷新。原配置事务、谓词、旧admission停点、SPSC无共享reader/pending RMW测试继续通过。

## 同条件测量

`zig build bench-routes -Doptimize=ReleaseFast -j1` 分别测量1/8/64个route的全部继承、混合与全部独立filter场景。调用公开Runtime.enabled，循环变化level和scope；配置建立、全组合oracle验证与分配在计时外，每批10000次、5次重复、一对单调时钟。输出checksum核对所有决策，runtime allocator在setup后拒绝新分配。

修改前完整源码独立冻结，应用与库同为ReleaseFast。固定一个CPU，五对进程交替before/after，225对报告中的checksum、输入和预算一致。本机中位ns/check：

| route数 | 规则形状 | before | after | 资格 |
| --- | --- | ---: | ---: | --- |
| 1 | 全部继承 | 25.62 | 25.60 | 小范围基本相同 |
| 8 | 全部继承 | 30.81 | 25.61 | 本机约17%降低 |
| 8 | 混合 | 31.23 | 25.49 | 本机约18%降低 |
| 8 | 全部独立 | 36.85 | 32.33 | 本机约12%降低 |
| 64 | 全部继承 | 101.31 | 25.61 | 跨轮spread超过10%，inconclusive |
| 64 | 混合 | 127.06 | 34.79 | 跨轮spread超过10%，inconclusive |
| 64 | 全部独立 | 210.27 | 142.68 | 本机约32%降低 |

这是enabled过滤成本，不能替代日志捕获、JSON编码、后台交付或文件I/O的吞吐。另用原snapshot公共基准保持memory队列、5个数字字段、ZeroClock、sleep worker及written确认，共40个共享/attached admission与完整日志试验完成；完整输出累计200000条accepted=written，pending/drop/测量期runtime分配为0。两种模式的完整性能比较均超过10%噪声门限，报告inconclusive，不宣称整体更快。

原始输入、二进制/源码身份和完整比较见 `bench/evidence/2026-11-01-route-selection/`。场景的min_level分布固定；不能把本机稀疏独立filter或level=off命中的结果概括到任意业务规则和机器。
