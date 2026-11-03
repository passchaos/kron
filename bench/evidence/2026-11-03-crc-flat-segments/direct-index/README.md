# 平坦固定段的直接scalar索引

这是初版POINTER物化重复old16KiB后的独立表示。firstsource/math/formula与所有失败证据保持；新shadow仅改变fixedWord的4个scalar访问，oldgeneralupdate/tables/extra生成、typed读取/seed/statewrite、format两调用及所有test保持。

通过comptime选择直接oldtables[row][byte]或extra[row-16][byte]，不取得row/array POINTER、不绑定1KiBrow值。目标是复用旧general已经引用的row常量；去重、rodata、加载地址、register/frame/call尚未证明。全部数值/读界/alias最小相关验证后冻结，再actual逐rowhash/address gate，通过才双拓扑140组CRC控制。无速度声明。

数学与canonical24row身份复用 [初版独立结果](../independent-math.json)，仅访问表示改变，实际newtyped执行另行绑定hash。测量使用父目录未改的 [measure_primitive.py](../measure_primitive.py) 与相同 [primitive.zig](../primitive.zig)，输出写本目录的独立window，不改初版任何source/bin/tar。
