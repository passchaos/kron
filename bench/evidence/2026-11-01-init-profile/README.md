# SPSC mmap initialization syscall observations

Baseline: `20d49be`, using the current-workflow frozen reference executable.
Four producer channels plus the shared journal have five mappings. Each is
preallocated, initialized and published before use: five fallocate, five
msync and ten file/directory fsync calls. The protocol is unchanged.

`syscalls.txt` is a strace CPU-time summary; syscall CPU accounting does not
include their wall wait and cannot explain cold initialization latency.
`timing.txt` separately records actual syscall wall durations (`-ttt -T`).
One heavily loaded-host 1-record invocation initializes in 5.106 seconds:
msync totals 3.085 seconds, file/directory fsync 2.016 seconds, fallocate
0.000099 seconds. An earlier 1000-record invocation initializes in 86.6ms.
These are tracing observations, not stable baseline rankings. All original
logs and the numerical duration extraction are retained.

The cases both use real files, 4 producers, SPSC mmap, 256 slots, 512-byte
payloads, no schema and a 64KiB output buffer. Init includes file sink,
configuration/runtime, all journal mappings and workers. The trace shows
material persisted-file/entry wait; it does not establish that preallocation,
CPU rendering or a journal deadlock caused the observed cold tail. Publication
remains mandatory before a logger can accept records.
