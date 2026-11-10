# Compressed binary archives

`CompressedArchiveSink` wraps any existing sink, takes complete KRONARC1 frames
with `Format.binary`, and outputs independent KRONCMP1 blocks. The algorithm is
standard RFC1950 zlib/DEFLATE with no external dependency.

```zig
const compressed = try kron.CompressedArchiveSink.create(allocator, .{
    .sink = file.sink(),
    .max_raw_bytes = 64 * 1024,
    .max_records = 256,
});
defer compressed.deinit();
// The route uses .sink = compressed.sink(), .format = .binary.
```

The block header is 32 bytes and stores magic, version, algorithm, raw/compressed
lengths, raw CRC32, frame count, and header CRC32. Each block decodes independently
and records inside are not split; buffers/workspace/window are allocated at
initialization, and normal write/flush does not allocate heap memory.

The block is cleared only after a successful child write+flush. A failure keeps
the same block, and retry may produce duplicates; if a partial write leaves a
corrupt tail, the storage owner must explicitly repair/truncate it, and the sink
never silently discards evidence. Durability capability follows the child and
waits for its sync.

`kroncat` automatically recognizes compressed archives and reads events after the
complete block passes CRC/count validation. A static truncated tail reports an
error, and follow waits for a complete block; an empty file or public magic prefix
can also wait for the first format determination. Read buffers and descriptor
arenas are preallocated, and the file is left unchanged.

Zig output has been independently decoded with standard Python zlib. A repeated-
metadata sample compressed to about 9.6% of its original size, while a random
64 KiB sample expanded slightly; compression consumes CPU and cannot promise
higher throughput. Tests cover algorithm/version, CRC, complete frames,
truncation, budgets, zero allocation, failed retry, durable forwarding, and
cross-language decoding.
