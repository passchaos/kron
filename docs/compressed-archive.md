# 压缩二进制归档

`CompressedArchiveSink` 包装任意已有sink，输入为 `Format.binary` 的完整KRONARC1 frame，输出独立的KRONCMP1 block。算法为标准RFC1950 zlib/DEFLATE，不依赖外部库。

```zig
const compressed = try kron.CompressedArchiveSink.create(allocator, .{
    .sink = file.sink(),
    .max_raw_bytes = 64 * 1024,
    .max_records = 256,
});
defer compressed.deinit();
// Route 使用 .sink = compressed.sink(), .format = .binary。
```

block头32字节，保存magic、版本、算法、原始/压缩长度、原始CRC32、frame数量和header CRC32。每个block独立解码，内部记录不拆分；buffer/workspace/window在初始化时分配，常规write/flush不分配堆内存。

成功child write+flush后才清空。失败保留同一block，重试可能产生重复；部分写导致损坏尾部时，存储owner需显式修复/截断，sink不会静默丢弃证据。durable能力沿用child并等待其sync。

`kroncat` 自动识别压缩归档，完整block通过CRC/count校验后读取事件。静态截断尾部报错，follow等待完整block；空文件/公共magic前缀也能等待首次格式确定。读取缓冲与descriptor arena预分配，并保持文件不变。

已用Python标准zlib独立解码Zig输出。重复metadata样本约压到原大小9.6%，随机64KiB样本略膨胀；压缩会消耗CPU，不能承诺提高吞吐。测试覆盖算法/版本、CRC、完整frame、截断、预算、零分配、失败重试、durable转发和跨语言解码。
