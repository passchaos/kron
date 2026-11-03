# Portable vs Linux io_uring后端诊断

当前`FileSink.Options`/`RollingFileSink.Options`默认`backend=.auto`，Linux会优先选择io_uring。用同一源码、同一reference binary对portable与linux_uring做完整文件流程A/B，确认deferred consumer批量写出下哪个后端应作为默认。

## 身份

- 源码基线：提交`92368f8`（本诊断后仅改默认backend与测试/文档）。
- runtime reference binary：`68c06b8109fad63fc8f345ea68882d6ad478b25198268bd3b2287be3a0590094`。
- managed诊断使用临时benchmark副本：把managed target的`.backend=.portable`改为`options.backend`并移除managed-only guard，binary `808248c2b639307b231b79894d654585a7ec9550121c90f5af2101960fbfb6e5`；生产与提交benchmark未改。
- 两者均为ReleaseFast、`buffer_bytes=65536`、真实ext4/NVMe文件、完整JSON输出；未请求durable。

## Runtime矩阵

`--frontend=runtime`，100k计时事件+1k warmup，12个配置（async/spsc × memory/mmap × P1/P4 × batch/sampled）× 2 reps，portable/linux_uring交替。`written_records_per_sec`中位比（uring/portable）：

| mode | storage | P | phase | written ratio | lifecycle ratio |
| --- | --- | ---: | --- | ---: | ---: |
| async | memory | 1 | batch | 0.8182 | 0.8196 |
| async | memory | 1 | sampled | 0.8098 | 0.8119 |
| async | memory | 4 | batch | 0.7577 | 0.7611 |
| async | memory | 4 | sampled | 0.8264 | 0.8244 |
| async | mmap | 1 | batch | 0.8251 | 0.8981 |
| async | mmap | 1 | sampled | 0.8608 | 0.9233 |
| async | mmap | 4 | batch | 0.7229 | 0.7516 |
| async | mmap | 4 | sampled | 0.7483 | 0.7781 |
| spsc | memory | 1 | batch | 0.8388 | 0.8392 |
| spsc | memory | 1 | sampled | 0.8111 | 0.8101 |
| spsc | mmap | 1 | batch | 0.8671 | 0.9058 |
| spsc | mmap | 1 | sampled | 0.8081 | 0.8439 |

**12/12配置io_uring更慢**，written中位低约13%–28%。另有200k P4 mmap batch三对交替：written ratio 0.9876/0.8534/0.8513，median portable 2.31M vs uring 2.04M records/s。原始row见[results-runtime.jsonl](results-runtime.jsonl)与[results-p4-mmap-200k.jsonl](results-p4-mmap-200k.jsonl)。

## Managed矩阵

`--frontend=managed`，100k事件、P4、async、memory/mmap、batch/sampled × 2 reps。由于managed路径的`backend_selected`仍只从独立FileSink读取，raw row会报告`portable`；实际后端由`backend_requested`区分。

| storage | phase | portable written | uring written | written ratio | lifecycle ratio |
| --- | --- | ---: | ---: | ---: | ---: |
| memory | batch | 2.47M | 2.11M | 0.8519 | 0.8559 |
| memory | sampled | 2.38M | 1.87M | 0.7843 | 0.7831 |
| mmap | batch | 2.54M | 1.89M | 0.7448 | 0.7534 |
| mmap | sampled | 2.47M | 2.11M | 0.8572 | 0.8612 |

**4/4 managed配置io_uring更慢**。原始row见[results-managed.jsonl](results-managed.jsonl)。

## 决策

portable在20/20个完整流程比较中更快；io_uring的SQE/CQE提交与完成等待没有与格式化重叠，只增加每批成本。因此把`FileSink.Options`与`RollingFileSink.Options`的默认backend从`.auto`改为`.portable`，`.auto`/`.linux_uring`继续显式可选。新增`file sink default backend is portable and remains writable`测试锁定默认与实际写出。

该改动不改变官方跨库benchmark：managed reference原本就显式使用`.portable`，所以Foundation排名与已有完整矩阵不因本诊断变化。它不是新的跨库速度声明，也不替代其他后端/文件系统/设备资格。

## 边界

诊断使用单机Linux ext4/NVMe、64KiB buffer、deferred consumer与现有flush边界；不代表io_uring在更深队列、其他文件系统或不同设备上永远更慢。没有durable flush、没有跨库trial、没有更新Foundation排名。整体“业界最佳”目标仍未完成。
