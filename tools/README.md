# 日志查看工具

`zig build` 安装 `kroncat` 和 `kron-bench`。kroncat 的实现是 [kroncat.zig](kroncat.zig)，支持本地自包含归档与 journal 的只读导出、查询和 follow。

```sh
zig-out/bin/kroncat --json --recover app.journal
zig-out/bin/kroncat --follow --level warn app.kron
zig-out/bin/kroncat --json --where 'request_id == "abc"' app.kron
```

schema 定义与事件载荷各自校验，不依赖已经退出进程的二进制。只读恢复/inspection 不修改原 journal，也不替代 Runtime 的稳定输出身份校验与恢复交付。编码、坏尾部、历史版本与压缩支持见 [编码](../docs/encoding.md)、[schema](../docs/schema.md)、[压缩归档](../docs/compressed-archive.md)。

## 证据索引

`python3 tools/bench_index.py` 重新生成 [bench/evidence/INDEX.md](../bench/evidence/INDEX.md)；`--check` 只校验不写入，适合提交前或 CI。索引从每个实验目录的 `README.md` 首标题和 `manifest.json` 是否存在生成，不解析测量结果；新实验从 [TEMPLATE.md](../bench/evidence/TEMPLATE.md) 开始。

`python3 tools/check_repo_hygiene.py` 检查 tracked 文件是否命中 `.gitignore`、是否混入缓存/生成物、是否还有 `reference-*` 可执行副本、raw tar/perf/data 文件，以及是否有超过 8 MiB 的单文件；`zig build hygiene` 是同一检查的构建入口。

`python3 tools/check_links.py` 检查 tracked Markdown 的相对链接，跳过 HTTP/mailto/anchor 和 fenced code block；`zig build links` 是同一检查的构建入口。

`zig build test-query -Doptimize=ReleaseSafe -j1` 验证 Reader/查询/follow。真实子进程强杀与只读导出由 `test-crash`、`test-async-crash` 和 `test-runtime-crash` 验证，测试入口见 [tests/](../tests/README.md)。
