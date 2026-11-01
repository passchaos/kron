# Current complete-file user PMU profile

Measured baseline: `20d49be`; binary identity is verified against the current
Foundation/spdlog/kron full-workflow manifest and stored in `identity.json`.
P4 SPSC-memory, 1,000,000 measured events plus 1000 warmup, system clock,
full JSON, real file, 256-slot/512-byte payloads and 64KiB file buffer.
Independent full-workflow oracle verifies all **1,001,000 physical records**;
accepted=written=1,000,000, drop/pending=0, full IDs/fields/bytes checked.

`report.txt` preserves the user-cycle profile and call chains. 1342 samples,
no lost samples. Self samples are about 11.9% memcpy, 10.9% submit destination,
8.3% fused wire render, 7.4% CRC and 7.1% scalar/nested value output. Sampled
small memcpy call chains include decimal temporary-to-Writer copies. These
percentages are diagnostic samples, not exact cost proportions or proof of
end-to-end gains. Startup, producer/consumer, close and cleanup are included.

`before.perf.data.gz` losslessly preserves the original perf.data; the raw
SHA256 and gzip SHA256 are in identity.json. Decompress to a temporary path
and use `perf report --stdio -i PATH` to inspect it. Generated output stays
under artifacts/ and is excluded from Git/source-package staging.
