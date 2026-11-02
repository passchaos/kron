# IEEE CRC四lane并行合并

本轮候选只把PCLMUL四个lane的三层串行合并改为等价的直接合并。相同六次乘法独立执行，原payload block循环、header20/reference24/payload分段、短tail、seed/final XOR、多项式与所有三个记录校验点保持。没有增加Runtime内存或队列预算。Zig native x86_64且目标声明PCLMUL/SSE2时生效，generic/non-x86仍使用原portable CRC。

## 数学与源码

令normal IEEE generator为P=0x104c11db7，反射域距离d的常数为`{reverse32(x^(d+32) mod P)<<1, reverse32(x^(d-32) mod P)<<1}`。该公式重新推导原128/512bit常数并得到256/384bit新常数：

| 距离 | low | high |
| --- | --- | --- |
| 256bit | 0x00f1da05aa | 0x015a546366 |
| 384bit | 0x003db1ecdc | 0x0174359406 |

`F384(x1) ^ F256(x2) ^ F128(x3) ^ x4`替换三轮`F128`。中间128bit代表元可以不同，CRC余数及后续fold结果必须相同。`math_probe.py`独立normal-polynomial证明512项fold基、1536项collapse基并对396个任意raw seed随机数据执行bitwise IEEE/zlib双oracle。native探针39312个seed/长度/对齐案例、1536个硬件输入基及中间分段state通过。源码自带新常数生成测试和512个输入基的独立std IEEE oracle。

`primitive/serial|direct|tree`冻结原根与两个只改collapse的根。CPU30、25长度×两种schema×5内部重复×5invocation×3variant共3750行，全checksum相同，原始输出无损压缩保留。受影响34组中，direct中位配对速度比几何均值1.0555×，tree1.0352×；direct在31/34组较tree快。direct v1 64/128/256/512B约1.085/1.067/1.076/1.058×，2048/16384B基本1.00×。serial部分invocation max/min达1.329，不能把这个primitive作为完整日志性能资格。

基线为`1bc811f`的冻结src，生产候选hash/二进制在`provenance.json`，完整源在`before-source.tar.xz`/`candidate-source.tar.xz`和`crc.patch`。两种候选与证明代码另存`candidate.zig`、`frontend.zig`、`exports.s`；standalone assembly两方案均6CLMUL，无SIMD stack访问，direct常数load从1增至3。这不是完整logger栈帧或寄存器压力证明。

## 完整文件结果

公共managed async/SPSC，Memory/Mmap、P1/P4、batch/sampled，系统时钟、五typed数值fields、256槽/512B、64KiB portable文件，100k事件+1000warmup，written flush→shutdown→cleanup。每个topology160项全部逐条核对16,160,000条JSON，默认CRC、pending/drop=0；不请求设备durable。

| 拓扑 | 关闭吞吐配对局部领先 | 局部负向 | 不确定 |
| --- | ---: | ---: | ---: |
| E-core CPU16/18/20/22/24/26 | 4 | 0 | 12 |
| P-core CPU0/2/4/6/8/10 | 2 | 1 | 13 |

E-core多数配对中位为正：async Memory P4 batch约1.038×但仍inconclusive；SPSC Mmap P1 batch约1.025×取得局部资格。P-core async多数配对中位为正，SPSC Memory P1 batch却0.957×并取得局部负向资格，不能忽略。该场景另5对百万条完整日志复测，核对10,010,000条JSON：配对中位1.025×、95%区间0.980..1.034，未复现短流程负向，仍不确定。前一负向保留，不外推为一般收益。

调用尾部大多不确定：P1一些p99.9负向中位和较大spread仍在原数据。E-core SPSC Mmap P4 sampled p99.9局部速度比1.026×，P-core SPSC Memory/Mmap P4 sampled p99.9约1.060/1.036×取得局部资格；不表述为所有尾延迟更低。初始化与完整生命周期独立报告。

额外E-core40项完整shared文件PMU核对4,040,000条JSON。用户instructions约增加0.06%–0.08%，Memory P1及Mmap P1/P4有局部轻微负向资格；cycles配对中位约降低1.9%–5.2%，只有Mmap P1通过本轮门限，95%速度比区间1.050..1.078。其余cycles与完整吞吐仍不确定。PMU包括完整子进程setup，排除kernel，不能以instructions小幅增加或cycles减少单独推导跨库排名。

原始正负结果在`ecore-workflow/`、`pcore-workflow/`、`pcore-spsc-p1-long/`、`pmu/`。全部370项核对46,370,000条JSON；这些是kron before/after，没有Foundation同轮排名。下一验收必须使用相同候选源码与两个真实Foundation前端同轮比较。

随后以相同生产源码完成Foundation/logging + spdlog及+tracing的P-core/E-core各160项同轮矩阵，总核对32,320,000条JSON。E-core对spdlog 16对中kron领先2、peer领先5、不确定9；对tracing peer领先14、不确定2，目标未达到。P-core对spdlog kron领先3、不确定13；对tracing kron领先6、不确定10，整体inconclusive。两种拓扑没有证明全面超过两个前端，源/依赖/二进制和所有完成阶段见[当前E-core矩阵](../../cpp_reference/evidence/2026-11-02-crc-parallel-collapse-ecore/README.md)、[P-core矩阵](../../cpp_reference/evidence/2026-11-02-crc-parallel-collapse-pcore/README.md)。前后百分比不与这次跨库比值相加。

## 验证范围

CRC模块native Debug/Safe/Fast各6/6，generic Safe 3通过/1 native-only skip；journal旧v1/v2 golden通过。`src/core/tests/runtime_admission_shutdown.zig`另外保留从共享分片实验发现的真实futex final-admission无记录唤醒回归；共享分片生产源码已撤回，其资源/cycles数字不与本轮相加。

完整ReleaseSafe、源码分发、单线程、真实SIGKILL与九目标object门禁149/149步骤成功、621/622测试通过（1项默认未链接系统local能力skip），见`full-safe.log`。独立local专项实际执行六时区×五模式oracle，regex/decoder/schema矩阵、随机/边界SIGKILL与源码包均通过。非Linux object不代表设备运行，SIGKILL不代表物理掉电。

```sh
python3 bench/cpp_reference/compare_versions.py --before BEFORE --after AFTER \
  --output-dir FRESH --affinity 16,18,20,22,24,26 \
  --events 100000 --repeats 5 --modes async,spsc
python3 bench/cpp_reference/compare_versions.py --before BEFORE --after AFTER \
  --output-dir FRESH --affinity 0,2,4,6,8,10 \
  --events 1000000 --repeats 5 --modes spsc --storages memory --producers 1 --phases batch
zig build verify-local test-package-distribution check-platforms -Doptimize=ReleaseSafe -j1 --summary all
```
