# 当前 managed Logging / Foundation spdlog / Rust tracing

完整结果见 [详细比较](detailed-comparison.md)。JSON同轮160试验/1616万条，原生tracing文本控制40试验/404万条，所有实际输出核对通过；包含全部关闭和清理，初始化另列。5次重复、P1/P4、Memory/Mmap、256槽、512B record、64KiB输出buffer、block/written、CPU affinity 0/2/4/6/8/10。

当前kron基于58a9a9b，包含owner借用、小Frame和fanout拆分。通过Logging公开入口测量，SPSC采用实际默认spin；Rust公共JSON使用Subscriber/fmt+TracingMakeWriter，标准文本使用原生build_tracing，保留其不同的优化writer。常规JSON速度比不混入原生文本数字。Foundation仓库保持只读，只在冻结副本加入本仓库的基准bin，Cargo.lock未改动。

主矩阵JSON元数据与五个数值字段相同，session设为同一固定宽度测试值；每库的sequence分配方式和队列协议仍不同。kron的SPSC多队列预算、配置版本/CRC/恢复、consumer格式化和Foundation producer文本捕获的取舍需结合原始数据判断。功能并非全部同时开启，详见profile说明。

当前稳态中位多数高于Foundation+spdlog；与Rust公共JSON组合互有胜负，P1 Memory落后而P4 SPSC中位领先。全部跨库速度比因重复性spread或区间跨1仍为inconclusive；p99.9与Mmap初始化仍有显著差距。宿主load约87，未独占CPU和存储。

`json/`、`native/`保留全部原试验、清理后文件哈希、min/max、完整阶段、source/binary/依赖与构建命令。`measured-source.tar.xz`冻结kron生产源码、各适配器、验证脚本和报告生成器；各子目录冻结Foundation源码。qualification.json核对当前生产与基准源码SHA256，记录归档hash。非Linux设备和物理掉电不在本轮性能资格中。

```sh
python3 bench/cpp_reference/run.py --output-dir /tmp/kron-frontends-json --libraries foundation,foundation_tracing,kron --kron-frontend managed --kron-schema off --events 100000 --warmup 1000 --repeats 5 --producers 1,4 --discard-artifacts
python3 bench/cpp_reference/run.py --output-dir /tmp/kron-frontends-native --libraries foundation_tracing --metadata native_tracing --events 100000 --warmup 1000 --repeats 5 --producers 1,4 --discard-artifacts
```
