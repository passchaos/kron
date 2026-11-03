# Sharded admission候选诊断

尝试把shared async producer的admission gate从单个cacheline RMW改为per-thread分片计数，以降低P4 begin/end争用。两版候选均完成正确性门禁；E-core空闲窗口20对A/B显示v2稳定回退，且Runtime对象超出既有预算，生产已撤回。

## 设计

- v1：保留一个`state`关闭/截断字；每个线程固定选择一个cache-line分隔的shard counter，begin在shard上`fetchAdd`后再次读取state以处理close/cut竞争。close/cut设置state并sum所有shard。
- v2：每个shard word同时携带closing/cut/count，begin只在该shard上CAS；close/cut先发布全局`flags`供`enabled`快速检查，再在所有shard设置bit并sum等待。去掉了begin后的全局state读取。
- 两版都用TLS记录shard，并在admission frame中保存shard供end释放。

## 正确性

- v1与v2均在`zig build test -Doptimize=ReleaseSafe -j1`通过**65/65 steps、748/749 tests（1项local skip）**，包括admission lifecycle、shared view、shutdown唤醒、close/cut与prepared/thread路径。
- 候选源码见[candidate.patch](candidate.patch)。

## PMU（P-core，runtime async memory P4 batch，500k events，baseline/candidate交替）

- v1：instructions约+0.5%–1.5%，但cycles五对均低于baseline约10%–20%（例如2.40B→1.88B、2.43B→2.12B）。原始输出见[pmu-p4-v1.txt](pmu-p4-v1.txt)。
- v2：instructions约+0.2%–0.9%，cycles两对下降、一对上升，方向不稳定。原始输出见[pmu-p4-v2.txt](pmu-p4-v2.txt)。

## 吞吐窗口

当前host `load average`约**125**，同时有sibling repo的`timez`/`horizon`/`iris` Zig构建和长时间`test`进程占用多个核（见[host-load.txt](host-load.txt)）。快速A/B出现0.61–1.60的成对written ratio，P1与P4均无法区分信号与调度噪声：

- v1 P4 written ratios：0.9406/1.3781/1.0463/0.9482/1.0285；P1：0.9779/1.0034/0.9839/0.9804/1.0159。
- v2 P4：0.9223/0.8241/0.9697/0.6103/0.9197；P1十对：0.9927/0.657/0.9424/0.6309/1.5958/0.9934/0.6756/0.8404/0.832/0.584。

原始row见[ab-p4-v1.jsonl](ab-p4-v1.jsonl)、[ab-p1-v1.jsonl](ab-p1-v1.jsonl)、[ab-p4-v2.jsonl](ab-p4-v2.jsonl)、[ab-p1-v2.jsonl](ab-p1-v2.jsonl)。该窗口不满足CV/spread资格，不能据此声称领先或回退。

## Idle E-core确认窗口

host高负载时P-core被sibling构建占满，但`mpstat`显示E-core（16–31）大多空闲。使用仓库既有E-core affinity `[16,18,20,22,24,26]`、runtime async memory P4 batch、500k events、20对baseline/candidate交替：

- baseline written中位**1,756,758** records/s；
- candidate written中位**1,710,756** records/s；
- 成对ratio median **0.9672**、mean **0.9595**、stdev **0.047**；20对中18对低于baseline。

这是一个稳定回退信号，v2分片admission在更安静的E-core窗口没有吞吐收益。原始row见[ab-p4-v2-ecore.jsonl](ab-p4-v2-ecore.jsonl)。

## 对象预算

- baseline `Runtime=12800`、`Journal=768`、`Field=48`。
- candidate `Runtime=13376`、`Journal=768`、`Field=48`，即**+576B**（8个cache-line shard + flags），超出既有Runtime预算。见[sizes.txt](sizes.txt)。

## 决策

E-core安静窗口的20对A/B显示v2稳定回退（median ratio 0.9672、18/20 negative），加上Runtime对象+576B超出既有预算，候选**拒绝并撤回**；`src/core/admission.zig`与`src/core/runtime.zig`恢复基线，生产无改动。保存patch与全部原始数据；不再以P-core高负载窗口的cycles信号作为保留依据，也不更新Foundation排名。

## 边界

没有完整managed dual-topology trial或Foundation对照；E-core A/B是runtime frontend的500k event诊断，不是正式双拓扑资格。候选仅在进程内shared async路径尝试，SPSC/thread-registry gate未改。整体“业界最佳”目标仍未完成。
