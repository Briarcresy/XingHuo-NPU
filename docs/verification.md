# 验证方法

## 为什么需要golden model

RTL和软件参考模型使用两套独立实现。Python根据公开数学规格计算expected，C++只负责
把输入送入Verilator模型并比较结果。这样能够避免把RTL自身的错误复制成测试答案。

```text
Python输入生成器 ──→ Python golden model ──→ expected
        │
        └────────────→ Verilator C++驱动 ──→ actual
                                             │
                                  expected ←─┘ 比较
```

## 测试分层

1. `tests/test_golden_model.py`检查打包、矩阵次序、Bias广播、舍入、饱和和回绕规则；
2. `generate_vectors.py`生成12个定向用例和默认1000个随机用例；
3. `XingHuo_NPU_sim.cpp`连续执行所有用例，验证握手和数据通路不会跨任务污染。

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
make test
```

生成的向量、Verilator模型和日志统一位于`build/`，不提交Git。
