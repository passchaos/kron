# 日志对应用工作量的影响

`bench/application.zig` 使用公共kron API，把相同的应用计算分别放在无logger、共享Memory、SPSC Memory、共享Mmap和SPSC Mmap的运行中。完整计时包含生产者任务、最终written flush、shutdown和Runtime/FileSink清理；日志初始化与应用数据准备单列。应用工作集与sample存储用于基准，最终报告/排序及基准存储释放不计入完整日志完成区间。

这是两个明确的合成请求模型：compute每线程2KiB数据，执行64次相依整数mix/状态更新；cache每线程1MiB数据，执行32次数据相关位置更新。请求结果会更新工作集，所有结果合成每线程sum/xor校验和，防止无日志路径的计算被优化掉。独立Python模型按相同请求编号与状态转移计算预期结果，并核对每个实际日志result。它们模拟计算与缓存访问，不代表某个真实业务服务或冷缓存资格。

| 选项 | 范围 |
| --- | --- |
| `--mode=none/shared/spsc` | 无日志应用、普通共享异步、每线程SPSC |
| `--storage=memory/mmap` | 已启用logger的队列存储；无logger报告none |
| `--work=compute/cache` | 小工作集计算或1MiB每线程数据相关更新 |
| `--operations=N` | 所有线程合计请求数，1..1000000，至少等于producer数量 |
| `--producers=1/4/16` | 应用线程数量；与CPU mask大小分开报告 |
| `--every=N` | 全局request_id每N条请求产生日志，1..1024 |
| `--sampled=true/false` | 单次应用操作（计算＋可选日志）分位数或batch计时 |
| `--warmup=N` | 合计0..10000个预热请求，计时前重置应用状态 |
| `--output=PATH` | 真实完整JSON文件；无logger不创建该文件 |

每条日志包含完整系统时间和关联元数据，以及request_id/result/producer/rounds/warmup五字段。Memory不恢复pending，Mmap具有原进程恢复协议，二者始终单列。无logger不会调用logger或获取事件时间，保留全部应用状态计算。该基线测的是关闭日志功能的应用成本，不将无日志计时包装成日志producer latency。

正式运行固定256槽、512-byte record、64KiB文件缓冲、睡眠worker、block过载和默认四个服务量子；所有logger/sink对象初始化后使用失败allocator，证明运行期没有新增runtime分配。应用工作集/sample存储和std.Io/线程宿主属于独立基准资源，不宣称整个进程零分配。每次测量使用新路径，逐条核验warmup与正常事件、结果、重复/缺失记录、每channel sequence和实际SPSC附件身份后才删除产物。

日志频率按全局request_id取模，request_id按producer交错分配。稀疏`every=16`在P4/P16下会集中于producer0的请求；此项代表稀疏而集中的日志源，不能当作每线程均匀日志。`every=1`则覆盖每个producer的日志。默认驱动选六个物理核的CPU mask0/2/4/6/8/10，P16会超额订阅；affinity不会保留CPU或屏蔽宿主负载。

```sh
zig build bench-application -Doptimize=ReleaseFast -- --output=.zig-cache/application.log --mode=shared --storage=memory --work=cache --producers=4 --every=16
zig build test-application-bench -Doptimize=ReleaseSafe -j1
python3 bench/application_compare.py --binary /path/to/kron-application-bench --output /path/to/fresh-capture --pmu
```

驱动默认两个模型、P1/P4/P16、every1/16、五种模式各五次，共300项batch试验。`--smoke`执行15个小规模实际场景，包括sampled和P16，只有正确性结论。PMU计量整个子进程的用户态instructions/cycles/cache-misses及context-switches/task-clock，包含初始化、准备、输出报告，排除内核硬件事件；它与完整计时范围不同。每个计数保留覆盖率，不支持/未计数的cache事件明确为unavailable；计数覆盖不足90%时不作稳定差异资格。

应用吞吐、阶段时间和CPU等指标按五项子进程结果报告median/CV/spread/bootstrap区间，所有慢值保留。无logger与日志组的共同计算校验和必须一致。噪声超10%或区间重叠使比较inconclusive。单项局部差异不替代所有负载的“业界最佳”结论；实测证据见`bench/evidence/2026-11-01-application-impact/`。

首轮正式300项完成，360万请求和165.756万日志核对通过，所有应用吞吐比较仍inconclusive。硬件计数覆盖率最低91%，部分instructions/task-clock差异有局部资格。完整正负中位与资源、cache-misses、context-switches分布见[应用影响报告](../bench/evidence/2026-11-01-application-impact/comparison.md)。当前实际服务仍需以其负载和日志策略建立自身基线。
