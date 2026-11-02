# E-core CRC候选完整前端对照

**此候选已撤回；本页不代表当前生产源码的新排名。** 精确生产源码逐文件哈希与二进制、Foundation原始源码/依赖、CPU/文件系统与负载身份在`manifest.json`。候选是原`97353ff`上的前缀拼接与4/8字节尾部切片，保留默认三个CRC校验和v1/v2协议。

CPU16/18/20/22/24/26，真实Foundation/logging + spdlog及+tracing，kron public managed async/SPSC、Memory/Mmap、P1/P4、batch/sampled，五次重复；100000事件+1000warmup、系统时钟、五typed数值字段、full JSON、256槽/512B、64KiB portable文件、written flush→shutdown→cleanup。160项全部通过物理JSON核对，共16,160,000条；drop/pending均为0。未请求设备durable。

按重复轮次配对的关闭吞吐资格：对spdlog的16对中，kron领先3、spdlog领先9、inconclusive 4；对tracing的16对中，tracing领先12、inconclusive 4。两侧和配对比值spread均≤10%、至少5轮及95%区间不跨1才判断局部领先；初始化、生命周期、p99/p99.9另列。完整数据与每项正负结果在`results.jsonl`、`analysis.json`和`comparison.md`。关闭吞吐目标为`target_not_met_in_selected_cases`。

候选的独立CRC长度负向结果和撤回决策见[完整实验](../../../evidence/2026-11-02-prefixed-crc/README.md)。此窗口不能外推P-core，不能把不同journal/CRC/恢复工作称为相同契约的普遍排名。

```sh
python3 bench/cpp_reference/run.py --output-dir FRESH \
  --libraries foundation,foundation_tracing,kron --kron-frontend managed \
  --kron-modes async,spsc --kron-storages memory,mmap \
  --events 100000 --warmup 1000 --repeats 5 --producers 1,4 \
  --metadata full --affinity 16,18,20,22,24,26 --discard-artifacts
python3 bench/cpp_reference/analyze.py FRESH
```
