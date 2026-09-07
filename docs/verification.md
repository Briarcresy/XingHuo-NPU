# 验证策略

验证包含以下层次：

1. `tests/test_golden_model.py`检查数值边界、溢出、量化和四组 XOR 真值表；
2. Python Golden Model 生成 1016 组 Core 定向/随机向量，C++ Verilator 驱动比较；
3. `XingHuoNpuTileTb.sv`通过外部协议验证160组两层网络（32组定向、128组随机），比较隐藏层、输出、分类、状态和错误码；覆盖0～31移位、高位忽略、溢出和连续任务；
4. Core 与 Tile SVA 检查握手、状态、RAM 写地址和复位输出等周期不变量；
5. 官方 Unit Test 与 Harness Test 检查 Tile Contract 和 Shared RAM 连接。
6. Icarus 四态 RTL 仿真使用未初始化 RAM 运行同样160组网络，并检查复位期间写禁止和复位恢复；
7. ICS55真实标准单元 Verilog 模型运行同一个四态测试，验证综合映射后的零延迟门级行为。

Tile边界测试还包括地址FF回绕、忙时请求延迟执行、85个运算/完成相对时刻复位、手动写/启动与模式请求的24组相对时序。Tile SVA在完整单元测试中启用，防止已接受事务在模式交接时丢失。两态Verilator的`$isunknown`不能替代四态仿真。

`sim/generate_xor_expected.py`从 Python Golden Model 生成 `tests/rtl/XorExpectedPkg.sv`，RTL Testbench 不手工维护 expected 数据。

```bash
make test
make lint
make official-check
make official-export
make gls ICS55_PDK=~/pdk/icsprout55-pdk
make multi-corner ICS55_PDK=~/pdk/icsprout55-pdk
make release-check
```

项目根目录存在 `mpsoc-digital/` 时会自动使用该模板；也可显式设置 `MPSOC_DIGITAL`。官方 `check`覆盖接口检查、Lint、Unit 与 Harness；`official-export`还生成最终 `Tile`并执行 `export-check`。本地通过不等价于官方通过，两者都应作为提交门槛。

`make release-check`重新运行本地验证、官方导出、门级仿真和PPA/多角估算，将源码哈希、工具版本、导出包和报告保存在`build/releases/`。任一步工具/功能检查失败，生成失败记录并停止；时序负裕量如实标为NOT_MET，不会宣称签核通过。

当前门级仿真没有SDF，SVA是仿真断言而非形式证明；尚未完成形式等价、CDC/RDC签核、DFT或布局布线后签核。PPA功耗仍为默认活动率估算。缺少的主办方输入与交接事项见[tapeout-readiness.md](tapeout-readiness.md)。
