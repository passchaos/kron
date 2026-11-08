# 完整日志流程实测（最终状态）

共 260 个试验，逐条核对 26,260,000 条完整日志。固定 CPU affinity：[16, 18, 20, 22, 24, 26]。kron durable 32 配置开启 backlog 自适应 `render_cache`；额外 4 个 `MmapSpool` 配置（P1/P4 × batch/sampled，非 durable）与同一 mmap peer 对照。peer 为 2026-11-04 冻结 binary（Foundation HEAD `0d1f5b0`）。

| 配置 | P1 batch | P1 sampled | P4 batch | P4 sampled |
| --- | ---: | ---: | ---: | ---: |
| kron async-memory-inline | 2.209 | 2.158 | 3.079 | 3.024 |
| kron async-memory-schema | 2.053 | 2.064 | 2.872 | 2.926 |
| kron async-mmap-inline | 2.208 | 2.113 | 3.023 | 3.028 |
| kron async-mmap-schema | 2.071 | 1.917 | 2.910 | 2.854 |
| kron spsc-memory-inline | 2.374 | 2.216 | 3.009 | 2.988 |
| kron spsc-memory-schema | 2.067 | 1.952 | 2.584 | 2.583 |
| kron spsc-mmap-inline | 2.370 | 2.253 | 2.996 | 3.027 |
| kron spsc-mmap-schema | 2.055 | 1.949 | 2.595 | 2.581 |
| kron spool (non-durable) | 3.265 | 2.870 | 8.565 | 7.568 |
| foundation memory | 1.817 | 1.721 | 2.204 | 2.245 |
| foundation mmap | 2.168 | 1.987 | 2.854 | 3.454 |
| foundation_tracing memory | 2.208 | 2.015 | 2.173 | 2.223 |
| foundation_tracing mmap | 2.829 | 2.445 | 3.283 | 2.671 |

## 配对资格

| kron 配置 | producers | phase | peer | ratio | 95% CI | 资格 | kron | peer |
| --- | ---: | --- | --- | ---: | --- | --- | ---: | ---: |
| async-memory-inline | 1 | batch | foundation | 1.2227 | 1.154..1.354 | inconclusive | 2.209M | 1.817M |
| async-memory-inline | 1 | batch | foundation_tracing | 1.0022 | 0.986..1.126 | inconclusive | 2.209M | 2.208M |
| async-memory-inline | 1 | sampled | foundation | 1.2528 | 1.181..1.316 | inconclusive | 2.158M | 1.721M |
| async-memory-inline | 1 | sampled | foundation_tracing | 1.0560 | 1.021..1.143 | inconclusive | 2.158M | 2.015M |
| async-memory-inline | 4 | batch | foundation | 1.3692 | 1.350..1.414 | kron_leads | 3.079M | 2.204M |
| async-memory-inline | 4 | batch | foundation_tracing | 1.3917 | 1.328..1.444 | kron_leads | 3.079M | 2.173M |
| async-memory-inline | 4 | sampled | foundation | 1.3687 | 1.330..1.376 | kron_leads | 3.024M | 2.245M |
| async-memory-inline | 4 | sampled | foundation_tracing | 1.3518 | 1.315..1.364 | kron_leads | 3.024M | 2.223M |
| async-memory-schema | 1 | batch | foundation | 1.1277 | 1.044..1.211 | inconclusive | 2.053M | 1.817M |
| async-memory-schema | 1 | batch | foundation_tracing | 0.9395 | 0.892..1.008 | inconclusive | 2.053M | 2.208M |
| async-memory-schema | 1 | sampled | foundation | 1.1904 | 1.100..1.224 | inconclusive | 2.064M | 1.721M |
| async-memory-schema | 1 | sampled | foundation_tracing | 1.0208 | 0.927..1.042 | inconclusive | 2.064M | 2.015M |
| async-memory-schema | 4 | batch | foundation | 1.3028 | 1.259..1.351 | kron_leads | 2.872M | 2.204M |
| async-memory-schema | 4 | batch | foundation_tracing | 1.3379 | 1.271..1.373 | kron_leads | 2.872M | 2.173M |
| async-memory-schema | 4 | sampled | foundation | 1.3152 | 1.283..1.352 | kron_leads | 2.926M | 2.245M |
| async-memory-schema | 4 | sampled | foundation_tracing | 1.3110 | 1.262..1.345 | kron_leads | 2.926M | 2.223M |
| async-mmap-inline | 1 | batch | foundation | 1.0093 | 0.996..1.062 | inconclusive | 2.208M | 2.168M |
| async-mmap-inline | 1 | batch | foundation_tracing | 0.7832 | 0.759..0.795 | peer_leads | 2.208M | 2.829M |
| async-mmap-inline | 1 | sampled | foundation | 1.0634 | 1.031..1.107 | kron_leads | 2.113M | 1.987M |
| async-mmap-inline | 1 | sampled | foundation_tracing | 0.8641 | 0.843..0.909 | peer_leads | 2.113M | 2.445M |
| async-mmap-inline | 4 | batch | foundation | 1.0499 | 1.000..1.088 | inconclusive | 3.023M | 2.854M |
| async-mmap-inline | 4 | batch | foundation_tracing | 0.9318 | 0.890..0.979 | peer_leads | 3.023M | 3.283M |
| async-mmap-inline | 4 | sampled | foundation | 0.8958 | 0.860..0.909 | peer_leads | 3.028M | 3.454M |
| async-mmap-inline | 4 | sampled | foundation_tracing | 1.1426 | 1.104..1.234 | inconclusive | 3.028M | 2.671M |
| async-mmap-schema | 1 | batch | foundation | 0.9528 | 0.935..0.987 | peer_leads | 2.071M | 2.168M |
| async-mmap-schema | 1 | batch | foundation_tracing | 0.7363 | 0.725..0.744 | peer_leads | 2.071M | 2.829M |
| async-mmap-schema | 1 | sampled | foundation | 0.9621 | 0.947..0.978 | peer_leads | 1.917M | 1.987M |
| async-mmap-schema | 1 | sampled | foundation_tracing | 0.7818 | 0.755..0.811 | peer_leads | 1.917M | 2.445M |
| async-mmap-schema | 4 | batch | foundation | 1.0104 | 0.959..1.046 | inconclusive | 2.910M | 2.854M |
| async-mmap-schema | 4 | batch | foundation_tracing | 0.8932 | 0.869..0.942 | peer_leads | 2.910M | 3.283M |
| async-mmap-schema | 4 | sampled | foundation | 0.8570 | 0.810..0.878 | peer_leads | 2.854M | 3.454M |
| async-mmap-schema | 4 | sampled | foundation_tracing | 1.0885 | 1.059..1.210 | inconclusive | 2.854M | 2.671M |
| spsc-memory-inline | 1 | batch | foundation | 1.2835 | 1.245..1.348 | kron_leads | 2.374M | 1.817M |
| spsc-memory-inline | 1 | batch | foundation_tracing | 1.0942 | 1.052..1.111 | kron_leads | 2.374M | 2.208M |
| spsc-memory-inline | 1 | sampled | foundation | 1.3103 | 1.278..1.350 | kron_leads | 2.216M | 1.721M |
| spsc-memory-inline | 1 | sampled | foundation_tracing | 1.1048 | 1.093..1.138 | kron_leads | 2.216M | 2.015M |
| spsc-memory-inline | 4 | batch | foundation | 1.3542 | 1.320..1.420 | kron_leads | 3.009M | 2.204M |
| spsc-memory-inline | 4 | batch | foundation_tracing | 1.3765 | 1.332..1.426 | kron_leads | 3.009M | 2.173M |
| spsc-memory-inline | 4 | sampled | foundation | 1.3419 | 1.322..1.371 | kron_leads | 2.988M | 2.245M |
| spsc-memory-inline | 4 | sampled | foundation_tracing | 1.3331 | 1.317..1.346 | kron_leads | 2.988M | 2.223M |
| spsc-memory-schema | 1 | batch | foundation | 1.1123 | 1.092..1.166 | kron_leads | 2.067M | 1.817M |
| spsc-memory-schema | 1 | batch | foundation_tracing | 0.9465 | 0.917..0.955 | peer_leads | 2.067M | 2.208M |
| spsc-memory-schema | 1 | sampled | foundation | 1.1552 | 1.081..1.219 | inconclusive | 1.952M | 1.721M |
| spsc-memory-schema | 1 | sampled | foundation_tracing | 0.9728 | 0.911..1.016 | inconclusive | 1.952M | 2.015M |
| spsc-memory-schema | 4 | batch | foundation | 1.1417 | 1.139..1.199 | kron_leads | 2.584M | 2.204M |
| spsc-memory-schema | 4 | batch | foundation_tracing | 1.1605 | 1.143..1.204 | kron_leads | 2.584M | 2.173M |
| spsc-memory-schema | 4 | sampled | foundation | 1.1485 | 1.141..1.174 | kron_leads | 2.583M | 2.245M |
| spsc-memory-schema | 4 | sampled | foundation_tracing | 1.1461 | 1.122..1.163 | kron_leads | 2.583M | 2.223M |
| spsc-mmap-inline | 1 | batch | foundation | 1.0812 | 1.051..1.150 | kron_leads | 2.370M | 2.168M |
| spsc-mmap-inline | 1 | batch | foundation_tracing | 0.8263 | 0.814..0.858 | peer_leads | 2.370M | 2.829M |
| spsc-mmap-inline | 1 | sampled | foundation | 1.1339 | 1.068..1.151 | kron_leads | 2.253M | 1.987M |
| spsc-mmap-inline | 1 | sampled | foundation_tracing | 0.9213 | 0.877..0.949 | peer_leads | 2.253M | 2.445M |
| spsc-mmap-inline | 4 | batch | foundation | 1.0466 | 0.978..1.101 | inconclusive | 2.996M | 2.854M |
| spsc-mmap-inline | 4 | batch | foundation_tracing | 0.9111 | 0.895..0.971 | peer_leads | 2.996M | 3.283M |
| spsc-mmap-inline | 4 | sampled | foundation | 0.8826 | 0.838..0.889 | peer_leads | 3.027M | 3.454M |
| spsc-mmap-inline | 4 | sampled | foundation_tracing | 1.1329 | 1.106..1.222 | inconclusive | 3.027M | 2.671M |
| spsc-mmap-schema | 1 | batch | foundation | 0.9520 | 0.904..1.022 | inconclusive | 2.055M | 2.168M |
| spsc-mmap-schema | 1 | batch | foundation_tracing | 0.7272 | 0.713..0.763 | peer_leads | 2.055M | 2.829M |
| spsc-mmap-schema | 1 | sampled | foundation | 0.9646 | 0.954..1.005 | inconclusive | 1.949M | 1.987M |
| spsc-mmap-schema | 1 | sampled | foundation_tracing | 0.7838 | 0.768..0.823 | peer_leads | 1.949M | 2.445M |
| spsc-mmap-schema | 4 | batch | foundation | 0.9159 | 0.827..0.931 | inconclusive | 2.595M | 2.854M |
| spsc-mmap-schema | 4 | batch | foundation_tracing | 0.7915 | 0.770..0.832 | peer_leads | 2.595M | 3.283M |
| spsc-mmap-schema | 4 | sampled | foundation | 0.7471 | 0.724..0.795 | peer_leads | 2.581M | 3.454M |
| spsc-mmap-schema | 4 | sampled | foundation_tracing | 0.9889 | 0.948..1.056 | inconclusive | 2.581M | 2.671M |
| spool | 1 | batch | foundation | 1.4901 | 1.462..1.561 | kron_leads | 3.265M | 2.168M |
| spool | 1 | batch | foundation_tracing | 1.1384 | 1.123..1.176 | kron_leads | 3.265M | 2.829M |
| spool | 1 | sampled | foundation | 1.4160 | 1.365..1.447 | kron_leads | 2.870M | 1.987M |
| spool | 1 | sampled | foundation_tracing | 1.1576 | 1.121..1.176 | kron_leads | 2.870M | 2.445M |
| spool | 4 | batch | foundation | 2.9275 | 2.523..3.049 | inconclusive | 8.565M | 2.854M |
| spool | 4 | batch | foundation_tracing | 2.6244 | 2.193..2.690 | inconclusive | 8.565M | 3.283M |
| spool | 4 | sampled | foundation | 2.2277 | 2.111..2.271 | kron_leads | 7.568M | 3.454M |
| spool | 4 | sampled | foundation_tracing | 2.8293 | 2.710..3.108 | inconclusive | 7.568M | 2.671M |

**汇总（含 spool）：29 kron lead、19 peer lead、24 inconclusive。**

