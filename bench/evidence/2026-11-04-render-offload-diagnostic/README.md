# Consumer render offload诊断

## 目的

批量确认后的profile显示consumer的JSON render约占总cycles的15.6%，consumer单线程同时承担decode+render+write。本诊断用两个shadow binary隔离render成本，判断下一候选应做“更快render”还是“把render移出consumer关键路径”。

## 方法

- `prod`：当前生产binary `1778caa...`（提交`e2934f8`）。
- `norender`：把`emitWireFused`的JSON render替换为固定299字节payload，保持同样的写出字节数；consumer仍做peek/CRC/release/write。
- `prodrender`：在`norender`基础上，每个producer在提交binary journal前额外调用一次`common.encodeDecoded(.json, ...)`并把结果丢弃，测量producer侧render的实际成本。
- 三个binary在E-core `[16,18,20,22,24,26]`上交替运行7轮；配置为P4、async、mmap、inline、batch、100k events、queue 256。
- 诊断binary的输出故意不是合法JSON，因此不做逐条输出验证；这里只比较`written_records_per_sec`上限，不是正确性或跨库排名。

## 结果

| binary | written median | runs (M/s) | 相对prod |
| --- | ---: | --- | ---: |
| prod | 1.830M | 1.834/1.812/1.830/1.827/1.841/1.828/1.883 | 1.00x |
| norender | 3.255M | 3.263/3.081/3.012/3.255/3.238/3.349/3.272 | 1.78x |
| prodrender | 3.007M | 2.994/2.761/2.687/3.037/3.216/3.073/3.007 | 1.64x |

结论：

- consumer JSON render是当前P4关键路径的最大单项成本；去掉render后write+CRC+bookkeeping上限约3.25M。
- 4个producer同时承担render仍有足够余量：producer render只把上限从3.25M降到3.01M，仍显著高于生产1.83M。
- 早期producer-format候选失败不是因为render工作本身，而是因为它把完整JSON写进journal payload，放大了CRC/内存流量和slot预算。下一候选应保留binary journal/CRC/recovery，把render结果放入独立的side buffer/queue，让consumer只写出；或在consumer内并行render。

## 边界

这是单窗口诊断，不是稳定吞吐资格；host load与E-core idle见[host-load.txt](host-load.txt)。诊断binary的源码补丁见[no-render.patch](no-render.patch)与[producer-render.patch](producer-render.patch)，binary身份见[binaries.sha256](binaries.sha256)，原始行见[results.jsonl](results.jsonl)。整体“业界最佳”目标仍未完成。
