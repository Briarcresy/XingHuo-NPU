# 验证方法

## 为什么需要Golden Model（黄金参考模型）

RTL和Software Reference Model（软件参考模型）使用两套独立实现。Python根据公开
数学规格计算expected，C++只负责
把输入送入Verilator模型并比较结果。这样能够避免把RTL自身的错误复制成测试答案。

```text
Python输入生成器 ──→ Python golden model ──→ expected
        │
        └────────────→ Verilator C++驱动 ──→ actual
                                             │
                                  expected ←─┘ 比较
```

## 测试分层

1. `tests/test_golden_model.py`检查打包、矩阵次序、Bias广播、Rounding（舍入）、
   Saturation（饱和）、Wraparound（回绕）和Overflow（溢出）规则；
2. `generate_vectors.py`生成16个定向用例和默认1000个随机用例；
3. `XingHuo_NPU_sim.cpp`连续执行所有用例，同时比较结果、错误码、6周期延迟和累计任务数；
4. `verification/XingHuo_NPU_assertions.sv`用SVA检查周期级协议不变量；
5. `verification/XingHuo_NPU_sva_tb.sv`定向触发错误状态、权重装载、切换和驻留计算。

全部批量用例都会先执行`Load Shadow → Switch Active → Start`，因此1016例都覆盖纯
Weight-resident Mode。NPU1.2新增的四个Directed Vector（定向向量）还验证同一Active Weight跨任务复用、
计算期间装载Shadow不会污染当前结果，以及切换后的结果只使用新Active Weight。
C++ Testbench还显式检查未装载启动、busy期间切换和空Shadow切换的Error Code；
SVA检查Bank Valid（存储组有效）状态的周期关系。

正式RTL继续使用IEEE Verilog-2005。SVA单独放在`verification/`，只用SystemVerilog
验证工具编译，不进入`filelists/rtl.f`或综合流程。

随机生成器使用固定seed。复现某次测试：

```bash
make sim TEST_COUNT=1000 TEST_SEED=0x20260831
```

失败时testbench最多详细打印前10例，包括解包后的矩阵、Bias、shift、expected和actual。
工具退出状态为非零，适用于脚本和CI。

## 常用命令

```bash
python3 -m unittest discover -s tests -v
make lint
make vectors
make sim
make sva-test
make test
```

生成的向量、Verilator模型和日志统一位于`build/`，不提交Git。
