# 短ASCII quoted合并写出：已否决

基线`117a63d`。候选只改`src/encoder/escaping.zig`的`quotedAscii`：对长度≤16的ASCII输入，把`" + input + "`复制进18字节栈buffer并一次`writeAll`，替代原来的三次writer调用；长输入保持原路径。输出字节完全相同。

## 决策

30项普通encoder probe交替PMU，每项300,000次scalar5/nested20/wide5编码、变动数值与完整输出hash。三种格式checksum/bytes一致，但JSON/text的instruction中位退化：

| 格式 | instructions | cycles | scalar5 | nested20 | wide5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| JSON | +2.72% | +5.10% | +4.04% | +9.00% | −1.41% |
| text | +2.75% | +4.09% | +5.33% | +6.21% | −2.45% |
| logfmt | −7.65% | −4.73% | +6.20% | −6.03% | −0.57% |

JSON/text是主要格式且instruction稳定退化；logfmt的下降没有在JSON/text复现，属于binary layout/窗口差异。栈复制和分支没有胜过直接writer调用，候选否决，生产源码已恢复`117a63d`。负向数据保留，避免再次以“减少writer调用”为由重做。

## 身份与复现

`before-provenance.json`/`after-provenance.json`固定基线/候选源码与encoder binary；`encoder-trials/`、`encoder-results.jsonl`、`encoder-comparison.json`保存全部30项原始CSV/row、慢值和重叠/稳定判定。

```sh
python3 bench/evidence/2026-11-02-quoted-ascii-short-compose/encoder_compare.py
```

脚本拒绝覆盖已有捕获；复跑前复制到新的evidence目录。本轮没有运行完整shared PMU或workflow。
