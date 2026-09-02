# 功能仿真

本目录采用“Python产生答案，C++驱动RTL”的Layered Verification（分层验证）结构：

- `golden_model.py`：独立实现NPU公开数值规格的Golden Model（黄金参考模型）；
- `generate_vectors.py`：生成定向输入和可复现的随机输入，并调用golden model计算expected；
- `XingHuo_NPU_sim.cpp`：读取向量、驱动Verilator模型并比较实际输出。

## 向量格式

生成文件默认为`build/sim/test_vectors.txt`。以`#`开头的是注释或元数据，其余每行
包含七个空白分隔字段：

```text
name activation_hex weight_hex bias_hex shift expected_hex error_hex
```

- `activation_hex`、`weight_hex`和`expected_hex`均为32位十六进制；
- 四个INT8元素从低位到高位依次为00、01、10、11；
- `bias_hex`为64位十六进制，低32位是`bias_0`，高32位是`bias_1`；
- `shift`为0～31的十进制整数；
- `error_hex`是Golden Model生成的预期Sticky Error Code（粘滞错误码）；
- 所有负数均使用二补码位型。

NPU1.2驻留权重测试从这些golden向量中选取专用定向用例，测试驱动只改变权重装载和
切换时序，不在C++中手算expected。

Core已移除Direct Mode。批量Testbench对每一个向量都执行：

```text
weight_load → weight_switch → start → wait(done) → compare
```

生成10个随机用例进行快速调试：

```bash
make vectors TEST_COUNT=10 TEST_SEED=123
make sim TEST_COUNT=10 TEST_SEED=123
```

默认值是1000个随机用例和固定种子`0x20260831`。失败信息会打印完整输入，使用同一
seed即可复现。
