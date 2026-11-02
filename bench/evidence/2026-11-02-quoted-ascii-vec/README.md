# quotedAscii改用writeVecAll：已否决

基线`bc908cc`。候选只把`src/encoder/escaping.zig`的`quotedAscii`从三次`writeByte/writeAll`改为一次`writeVecAll(&.{ "\"", input, "\"" })`，输出字节完全相同。

## 决策

30项普通encoder probe交替PMU，每项300,000次scalar5/nested20/wide5编码、变动数值与完整输出hash。三种格式checksum/bytes一致，但性能明显退化：

| 格式 | instructions | cycles | scalar5 ns/record | nested20 ns/record | wide5 ns/record |
| --- | ---: | ---: | ---: | ---: | ---: |
| JSON | +26.71% | +29.76% | +28.07% | +37.95% | +11.00% |
| text | +26.85% | +19.69% | +22.75% | +24.86% | +13.06% |
| logfmt | +0.56% | +1.23% | +6.12% | −0.53% | +8.03% |

`writeVecAll`的切片循环、`writeVec/writeSplat`和总长度检查对三个短slice的常见路径明显重于直接`writeAll`；该候选没有完整流程资格，生产源码已恢复`bc908cc`。负向数据保留，避免再次以“减少Writer调用”为由重做。

## 身份与复现

`before-provenance.json`/`after-provenance.json`固定基线/候选源码与encoder binary；`encoder-trials/`、`encoder-results.jsonl`、`encoder-comparison.json`保存全部30项原始CSV/row、慢值和重叠/稳定判定。复现命令：

```sh
python3 bench/evidence/2026-11-02-quoted-ascii-vec/encoder_compare.py
```

脚本拒绝覆盖已有捕获；复跑前复制到新的evidence目录。本轮没有运行完整shared PMU或workflow，也不涉及跨库排名。
