# Qualified TSC clock observation

The optional provider qualified on this x86_64 Linux host: invariant TSC,
CPUID leaf15 frequency2995200000Hz, measured2995114684Hz and40ppm sample error.
The single-thread read trial recorded100000 qualified reads and zero fallbacks.

Measured wall-clock batch costs were about18.35ns/call for NativeClock and
34.52ns/call for the qualified TSC provider. This conservative TSC path is
therefore slower in this observation. Fenced reads, coherent atomic calibration
loads and statistics are real costs; qualification is not evidence of faster
logging. Runtime keeps its normal std.Io clock default, NativeClock remains an
explicit alternative, and TSC selection is explicit.

[result.json](result.json) preserves the observed values; [manifest.json](manifest.json)
records executable/source identities. Reproduce with `zig build bench-tsc
-Doptimize=ReleaseFast`. Batch clock cost is separate from producer p99 and
complete output throughput, and this single run is not a regression threshold.

The later coherent TLS calibration cache avoids rereading every atomic field
for a stable instance/generation. A separately recorded [cache result](tls-cache-result.json)
qualified all100000 reads and measured22.88ns/call versus15.33ns NativeClock.
Unique instance cookies prevent same-address reuse from inheriting an old
calibration; refresh still uses the fully validated seqlock snapshot on a miss.
The provider improved in this observation but remains slower than native, so
there is still no automatic performance promotion.
