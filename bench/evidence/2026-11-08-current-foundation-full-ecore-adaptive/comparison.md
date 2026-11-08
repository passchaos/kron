# 完整日志流程实测（adaptive render_cache）

共 240 个试验，逐条核对 24,240,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。kron 全部配置开启 backlog 自适应 `render_cache`；peer 为 2026-11-04 冻结 binary（Foundation HEAD `0d1f5b0`）。

下表均为 5 次试验的中位数。吞吐单位为百万条/秒，包含 producer、后台格式化/文件写出和最终 written flush；关闭列进一步包含 shutdown 和对象清理。它们都没有请求设备 durable。

| 配置 | P1 batch | P1 sampled | P4 batch | P4 sampled |
| --- | ---: | ---: | ---: | ---: |
| kron async-memory-inline | 2.238 | 2.112 | 2.851 | 2.845 |
| kron async-memory-schema | 2.127 | 1.983 | 2.901 | 2.913 |
| kron async-mmap-inline | 2.217 | 2.082 | 2.908 | 2.893 |
| kron async-mmap-schema | 2.072 | 1.992 | 2.933 | 2.926 |
| kron spsc-memory-inline | 2.348 | 2.179 | 2.848 | 2.891 |
| kron spsc-memory-schema | 2.146 | 2.047 | 2.298 | 2.296 |
| kron spsc-mmap-inline | 2.310 | 2.186 | 2.876 | 2.952 |
| kron spsc-mmap-schema | 2.133 | 2.046 | 2.331 | 2.323 |
| foundation memory | 1.854 | 1.739 | 2.263 | 2.154 |
| foundation mmap | 2.118 | 1.995 | 2.872 | 3.407 |
| foundation_tracing memory | 2.221 | 2.017 | 2.208 | 2.215 |
| foundation_tracing mmap | 2.832 | 2.426 | 3.182 | 2.702 |

## 配对资格

比值大于 1 表示 kron 更快；至少 5 轮、两侧和配对比值 spread 均 ≤10%、95% 配对 bootstrap 区间不跨 1 才判断领先。

| kron 配置 | producers | phase | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | ---: | --- | --- | ---: | --- | --- | ---: | ---: |
| async-memory-inline | 1 | batch | foundation | 1.2073 | 1.125..1.289 | inconclusive | 2.238M | 1.854M |
| async-memory-inline | 1 | batch | foundation_tracing | 1.0079 | 0.966..1.073 | inconclusive | 2.238M | 2.221M |
| async-memory-inline | 1 | sampled | foundation | 1.2128 | 1.175..1.221 | kron_leads | 2.112M | 1.739M |
| async-memory-inline | 1 | sampled | foundation_tracing | 1.0417 | 1.012..1.059 | kron_leads | 2.112M | 2.017M |
| async-memory-inline | 4 | batch | foundation | 1.2927 | 1.228..1.310 | kron_leads | 2.851M | 2.263M |
| async-memory-inline | 4 | batch | foundation_tracing | 1.2809 | 1.258..7.981 | inconclusive | 2.851M | 2.208M |
| async-memory-inline | 4 | sampled | foundation | 1.3144 | 1.252..1.420 | inconclusive | 2.845M | 2.154M |
| async-memory-inline | 4 | sampled | foundation_tracing | 1.2920 | 1.280..1.340 | kron_leads | 2.845M | 2.215M |
| async-memory-schema | 1 | batch | foundation | 1.1434 | 1.099..1.158 | kron_leads | 2.127M | 1.854M |
| async-memory-schema | 1 | batch | foundation_tracing | 0.9518 | 0.915..0.982 | peer_leads | 2.127M | 2.221M |
| async-memory-schema | 1 | sampled | foundation | 1.1428 | 1.123..1.198 | kron_leads | 1.983M | 1.739M |
| async-memory-schema | 1 | sampled | foundation_tracing | 0.9837 | 0.964..1.042 | inconclusive | 1.983M | 2.017M |
| async-memory-schema | 4 | batch | foundation | 1.2947 | 1.224..1.350 | kron_leads | 2.901M | 2.263M |
| async-memory-schema | 4 | batch | foundation_tracing | 1.3137 | 1.276..8.073 | inconclusive | 2.901M | 2.208M |
| async-memory-schema | 4 | sampled | foundation | 1.3293 | 1.292..1.412 | kron_leads | 2.913M | 2.154M |
| async-memory-schema | 4 | sampled | foundation_tracing | 1.3110 | 1.285..1.382 | kron_leads | 2.913M | 2.215M |
| async-mmap-inline | 1 | batch | foundation | 1.0466 | 1.021..1.121 | inconclusive | 2.217M | 2.118M |
| async-mmap-inline | 1 | batch | foundation_tracing | 0.8054 | 0.713..7.634 | inconclusive | 2.217M | 2.832M |
| async-mmap-inline | 1 | sampled | foundation | 1.0437 | 1.026..1.073 | kron_leads | 2.082M | 1.995M |
| async-mmap-inline | 1 | sampled | foundation_tracing | 0.8628 | 0.842..0.893 | peer_leads | 2.082M | 2.426M |
| async-mmap-inline | 4 | batch | foundation | 1.0157 | 0.889..1.067 | inconclusive | 2.908M | 2.872M |
| async-mmap-inline | 4 | batch | foundation_tracing | 0.8715 | 0.825..0.951 | inconclusive | 2.908M | 3.182M |
| async-mmap-inline | 4 | sampled | foundation | 0.8368 | 0.800..0.854 | peer_leads | 2.893M | 3.407M |
| async-mmap-inline | 4 | sampled | foundation_tracing | 1.0908 | 1.016..1.179 | inconclusive | 2.893M | 2.702M |
| async-mmap-schema | 1 | batch | foundation | 0.9750 | 0.956..1.049 | inconclusive | 2.072M | 2.118M |
| async-mmap-schema | 1 | batch | foundation_tracing | 0.7292 | 0.681..7.802 | inconclusive | 2.072M | 2.832M |
| async-mmap-schema | 1 | sampled | foundation | 1.0000 | 0.982..1.045 | inconclusive | 1.992M | 1.995M |
| async-mmap-schema | 1 | sampled | foundation_tracing | 0.8330 | 0.817..0.858 | peer_leads | 1.992M | 2.426M |
| async-mmap-schema | 4 | batch | foundation | 1.0188 | 0.962..1.093 | inconclusive | 2.933M | 2.872M |
| async-mmap-schema | 4 | batch | foundation_tracing | 0.8923 | 0.863..0.974 | inconclusive | 2.933M | 3.182M |
| async-mmap-schema | 4 | sampled | foundation | 0.8357 | 0.779..0.869 | inconclusive | 2.926M | 3.407M |
| async-mmap-schema | 4 | sampled | foundation_tracing | 1.0620 | 1.015..1.199 | inconclusive | 2.926M | 2.702M |
| spsc-memory-inline | 1 | batch | foundation | 1.2631 | 1.216..1.278 | kron_leads | 2.348M | 1.854M |
| spsc-memory-inline | 1 | batch | foundation_tracing | 1.0640 | 1.016..1.074 | kron_leads | 2.348M | 2.221M |
| spsc-memory-inline | 1 | sampled | foundation | 1.2618 | 1.213..1.285 | kron_leads | 2.179M | 1.739M |
| spsc-memory-inline | 1 | sampled | foundation_tracing | 1.0949 | 1.040..1.099 | kron_leads | 2.179M | 2.017M |
| spsc-memory-inline | 4 | batch | foundation | 1.2949 | 1.220..1.395 | inconclusive | 2.848M | 2.263M |
| spsc-memory-inline | 4 | batch | foundation_tracing | 1.3567 | 1.272..7.930 | inconclusive | 2.848M | 2.208M |
| spsc-memory-inline | 4 | sampled | foundation | 1.3391 | 1.263..1.407 | inconclusive | 2.891M | 2.154M |
| spsc-memory-inline | 4 | sampled | foundation_tracing | 1.3409 | 1.280..1.364 | kron_leads | 2.891M | 2.215M |
| spsc-memory-schema | 1 | batch | foundation | 1.1600 | 1.130..1.182 | kron_leads | 2.146M | 1.854M |
| spsc-memory-schema | 1 | batch | foundation_tracing | 0.9726 | 0.945..0.981 | peer_leads | 2.146M | 2.221M |
| spsc-memory-schema | 1 | sampled | foundation | 1.1777 | 1.165..1.186 | kron_leads | 2.047M | 1.739M |
| spsc-memory-schema | 1 | sampled | foundation_tracing | 1.0137 | 0.993..1.029 | inconclusive | 2.047M | 2.017M |
| spsc-memory-schema | 4 | batch | foundation | 1.0468 | 0.970..1.074 | inconclusive | 2.298M | 2.263M |
| spsc-memory-schema | 4 | batch | foundation_tracing | 1.0452 | 1.012..6.431 | inconclusive | 2.298M | 2.208M |
| spsc-memory-schema | 4 | sampled | foundation | 1.0663 | 0.999..1.107 | inconclusive | 2.296M | 2.154M |
| spsc-memory-schema | 4 | sampled | foundation_tracing | 1.0683 | 1.007..1.085 | kron_leads | 2.296M | 2.215M |
| spsc-mmap-inline | 1 | batch | foundation | 1.0915 | 0.978..1.112 | inconclusive | 2.310M | 2.118M |
| spsc-mmap-inline | 1 | batch | foundation_tracing | 0.8096 | 0.746..8.271 | inconclusive | 2.310M | 2.832M |
| spsc-mmap-inline | 1 | sampled | foundation | 1.0978 | 1.086..1.141 | kron_leads | 2.186M | 1.995M |
| spsc-mmap-inline | 1 | sampled | foundation_tracing | 0.9039 | 0.899..0.939 | peer_leads | 2.186M | 2.426M |
| spsc-mmap-inline | 4 | batch | foundation | 1.0078 | 0.959..1.072 | inconclusive | 2.876M | 2.872M |
| spsc-mmap-inline | 4 | batch | foundation_tracing | 0.8861 | 0.856..0.998 | inconclusive | 2.876M | 3.182M |
| spsc-mmap-inline | 4 | sampled | foundation | 0.8519 | 0.804..0.885 | peer_leads | 2.952M | 3.407M |
| spsc-mmap-inline | 4 | sampled | foundation_tracing | 1.0955 | 1.035..1.221 | inconclusive | 2.952M | 2.702M |
| spsc-mmap-schema | 1 | batch | foundation | 1.0071 | 0.989..1.028 | inconclusive | 2.133M | 2.118M |
| spsc-mmap-schema | 1 | batch | foundation_tracing | 0.7658 | 0.691..7.643 | inconclusive | 2.133M | 2.832M |
| spsc-mmap-schema | 1 | sampled | foundation | 1.0293 | 0.994..1.034 | inconclusive | 2.046M | 1.995M |
| spsc-mmap-schema | 1 | sampled | foundation_tracing | 0.8485 | 0.814..0.863 | peer_leads | 2.046M | 2.426M |
| spsc-mmap-schema | 4 | batch | foundation | 0.8061 | 0.776..0.869 | inconclusive | 2.331M | 2.872M |
| spsc-mmap-schema | 4 | batch | foundation_tracing | 0.7443 | 0.683..0.768 | inconclusive | 2.331M | 3.182M |
| spsc-mmap-schema | 4 | sampled | foundation | 0.6759 | 0.635..0.701 | peer_leads | 2.323M | 3.407M |
| spsc-mmap-schema | 4 | sampled | foundation_tracing | 0.8657 | 0.811..0.967 | inconclusive | 2.323M | 2.702M |

**汇总：19 kron lead、9 peer lead、36 inconclusive。**

## 剩余 peer lead

| kron 配置 | producers | phase | peer | ratio |
| --- | ---: | --- | --- | ---: |
| async-memory-schema | 1 | batch | foundation_tracing | 0.9518 |
| async-mmap-inline | 1 | sampled | foundation_tracing | 0.8628 |
| async-mmap-inline | 4 | sampled | foundation | 0.8368 |
| async-mmap-schema | 1 | sampled | foundation_tracing | 0.8330 |
| spsc-memory-schema | 1 | batch | foundation_tracing | 0.9726 |
| spsc-mmap-inline | 1 | sampled | foundation_tracing | 0.9039 |
| spsc-mmap-inline | 4 | sampled | foundation | 0.8519 |
| spsc-mmap-schema | 1 | sampled | foundation_tracing | 0.8485 |
| spsc-mmap-schema | 4 | sampled | foundation | 0.6759 |
