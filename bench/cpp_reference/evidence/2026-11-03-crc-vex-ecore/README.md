# CRC VEX当前Foundation E-core对照

完成160项，逐条核对16,160,000条物理JSON。与Foundation/logging + spdlog及+tracing真实前端同轮比较，候选source/provenance在matrix后核对不变。

公共managed async/SPSC、Memory/Mmap、P1/P4、batch/sampled、100k事件+1000warmup、5次轮换、五typed数值字段/full metadata、system clock、256槽/512B、64KiB portable文件；written flush→shutdown→cleanup，无device durable。CPU16/18/20/22/24/26。

| 对照前端 | kron局部领先 | peer局部领先 | 不确定 |
| --- | ---: | ---: | ---: |
| Foundation + spdlog | 3 | 6 | 7 |
| Foundation + tracing | 0 | 10 | 6 |

written-close目标为`target_not_met_in_selected_cases`。E-core对tracing多数有稳定差距；对spdlog只有Memory P1的三个局部case领先，Mmap/P4仍落后或因噪声不确定。不能将CRC约0.7%指令减少叠加到跨库ratio；初始化、lifecycle和p99/p99.9各自独立资格。至少5对、两输入/paired ratio spread≤10%、95%区间不跨1才写局部领先。

完整比值、尾部、依赖/编译/source/binary身份见`analysis.json`、`comparison.md`、`manifest.json`和`kron-source-provenance.json`。本目录的`summary.json`是driver原始分组统计，paired qualification由`analysis.json`提供。Linux进程崩溃/非durable范围不扩展到物理掉电或非Linux设备。
