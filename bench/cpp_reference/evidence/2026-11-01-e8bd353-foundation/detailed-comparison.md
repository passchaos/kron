# e8bd353 与 Foundation Logging＋spdlog 完整流程对照

200项试验，逐条验证20,200,000条JSON。每项100k测量＋1k预热，五次重复；P1/P4分别表示1/4个producer。

吞吐单位M条/s，包含producer、后台格式化/文件写出、最终written flush、shutdown和清理；初始化与预热单列。

## 普通inline完整吞吐

| 存储 | producer | Foundation＋spdlog | kron shared | 相对变化 | kron SPSC | 相对变化 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
|memory|1|2.155|2.213|+2.67%|2.342|+8.67%|
|memory|4|2.317|2.215|-4.41%|2.391|+3.21%|
|mmap|1|1.886|2.227|+18.05%|2.322|+23.09%|
|mmap|4|2.097|2.239|+6.81%|2.360|+12.58%|

## 预注册schema完整吞吐

| 存储 | producer | Foundation＋spdlog | kron shared | 相对变化 | kron SPSC | 相对变化 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
|memory|1|2.155|1.819|-15.60%|1.986|-7.85%|
|memory|4|2.317|2.044|-11.79%|2.223|-4.04%|
|mmap|1|1.886|1.676|-11.16%|1.828|-3.09%|
|mmap|4|2.097|1.998|-4.69%|2.163|+3.18%|

## 调用延迟、启动与关闭

调用分位数来自独立sampled阶段，单位ns；其测量的是一次调用返回，包括满队列阻塞。它不是event到文件的可见延迟。

| 实现/队列 | P | p50 | p99 | p99.9 | init ms | preparation ms | flush µs | shutdown µs | cleanup µs | lifecycle ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
|foundation memory|1|349|540|27296|0.177|0.708|82.737|117.018|0.464|47.233|
|foundation memory|4|805|28689|36936|0.190|0.812|38.334|62.469|0.352|44.146|
|foundation mmap|1|493|868|2004|24.804|0.753|75.069|273.725|0.454|77.850|
|foundation mmap|4|991|7982|12750|22.728|0.696|7.689|66.243|0.363|70.924|
|kron async-memory-inline|1|371|639|17666|0.562|0.780|30.255|29.999|59.948|46.588|
|kron async-memory-inline|4|792|29333|38469|0.537|0.720|35.593|23.304|53.966|46.484|
|kron async-mmap-inline|1|326|638|16574|11.772|0.971|28.014|25.212|68.683|57.361|
|kron async-mmap-inline|4|826|29105|52425|18.702|0.820|33.025|20.687|55.381|71.246|
|kron spsc-memory-inline|1|386|598|14861|0.653|0.776|26.316|23.030|66.850|44.358|
|kron spsc-memory-inline|4|283|605|345167|0.926|0.708|174.230|23.611|85.732|43.439|
|kron spsc-mmap-inline|1|296|686|17272|28.964|0.711|37.491|24.217|72.656|72.748|
|kron spsc-mmap-inline|4|279|663|347492|1248.936|0.714|157.069|26.721|95.378|1290.771|
|kron async-memory-schema|1|541|856|1017|0.589|0.916|2.800|35.026|69.789|56.293|
|kron async-memory-schema|4|943|30416|65467|0.567|0.771|32.121|23.233|57.445|50.232|
|kron async-mmap-schema|1|527|1712|2492|14.236|20.092|2.525|66.962|70.057|579.501|
|kron async-mmap-schema|4|970|30396|67890|12.161|435.556|1.641|20.855|60.970|507.879|
|kron spsc-memory-schema|1|499|748|871|0.676|0.809|22.738|39.031|77.545|51.862|
|kron spsc-memory-schema|4|459|706|342314|0.937|0.783|171.434|20.561|81.795|46.716|
|kron spsc-mmap-schema|1|494|1620|2273|23.829|481.202|2.424|28.056|77.211|971.520|
|kron spsc-mmap-schema|4|483|1169|344051|896.002|18.755|215.939|23.913|82.864|953.507|

## 吞吐资格

CV与相对spread两侧均小于10%，且bootstrap中位区间不重叠，才将本机差异标为supported；其余为inconclusive。所有慢值保留。

| kron配置 | P | 相对吞吐变化 | Foundation CV/spread | kron CV/spread | 区间重叠 | 结论 |
| --- | ---: | ---: | ---: | ---: | --- | --- |
|async-memory-inline|1|+2.67%|52.21%/97.10%|2.25%/4.96%|是|inconclusive|
|async-memory-inline|4|-4.41%|46.23%/90.62%|4.17%/11.07%|是|inconclusive|
|async-memory-schema|1|-15.60%|52.21%/97.10%|3.09%/7.40%|是|inconclusive|
|async-memory-schema|4|-11.79%|46.23%/90.62%|2.36%/6.21%|是|inconclusive|
|async-mmap-inline|1|+18.05%|9.57%/21.70%|9.00%/19.55%|是|inconclusive|
|async-mmap-inline|4|+6.81%|6.59%/17.68%|6.55%/14.79%|是|inconclusive|
|async-mmap-schema|1|-11.16%|9.57%/21.70%|5.02%/12.35%|是|inconclusive|
|async-mmap-schema|4|-4.69%|6.59%/17.68%|9.18%/20.97%|是|inconclusive|
|spsc-memory-inline|1|+8.67%|52.21%/97.10%|8.29%/18.37%|是|inconclusive|
|spsc-memory-inline|4|+3.21%|46.23%/90.62%|2.24%/5.67%|是|inconclusive|
|spsc-memory-schema|1|-7.85%|52.21%/97.10%|2.23%/5.76%|是|inconclusive|
|spsc-memory-schema|4|-4.04%|46.23%/90.62%|1.25%/3.06%|是|inconclusive|
|spsc-mmap-inline|1|+23.09%|9.57%/21.70%|5.53%/14.61%|否|inconclusive|
|spsc-mmap-inline|4|+12.58%|6.59%/17.68%|6.04%/14.47%|是|inconclusive|
|spsc-mmap-schema|1|-3.09%|9.57%/21.70%|7.45%/19.17%|是|inconclusive|
|spsc-mmap-schema|4|+3.18%|6.59%/17.68%|9.43%/22.96%|是|inconclusive|

完整分布、阶段与百分位资格见detailed-analysis.json；初始化/预热/关闭各阶段中位数不能相加重建生命周期中位数。资源预算和语义差异见README.md。
