# “星火” NPU

星火NPU是一个用于学习、验证和小面积流片迭代的2×2对称INT8推理加速器。当前数据
通路为：

```text
INT8矩阵乘法 → INT32累加 → INT32 Bias → 重量化 → INT8饱和 → ReLU
```

正式RTL严格使用IEEE Verilog-2005；Python golden model独立计算期望结果；C++17
testbench通过Verilator批量验证RTL。

## 当前版本：NPU1.0

`NPU1.0`是星火NPU的第一个完整可验证版本，包含2×2 INT8矩阵乘法、INT32累加与
Bias、重量化、INT8饱和和ReLU，并已接入Python golden model、批量Verilator验证
以及ICS55 PPA评估流程。

## 目录结构

```text
src/          正式Verilog-2005 RTL
sim/          Python golden model、向量生成器和Verilator C++ testbench
tests/        Python golden model单元测试
filelists/    统一RTL文件列表
constraints/  基础时钟约束
docs/         架构、接口、量化和验证文档
ppa/          Yosys、ICS55与iEDA PPA评估流程
reference/    学习参考代码，不参与正式构建
build/        自动生成的向量、模型、日志和报告，不提交Git
```

## 快速开始

需要：

- Python 3.10或更新版本；
- Verilator；
- 支持C++17的C++编译器和GNU Make。

查看所有入口：

```bash
make help
```

检查全部正式RTL：

```bash
make lint
```

生成向量、构建模型并运行默认批量仿真：

```bash
make sim
```

默认生成12个定向用例和1000个固定种子随机用例。成功结果为：

```text
ALL 1012 TESTS PASSED
directed=12 random=1000 seed=0x20260831
```

修改随机数量和种子：

```bash
make sim TEST_COUNT=10000 TEST_SEED=12345
```

单独测试Python golden model：

```bash
python3 -m unittest discover -s tests -v
```

运行全部开源验证：

```bash
make test
```

清理功能仿真生成物或全部生成物：

```bash
make clean-sim
make clean
```

## 数值格式

- Activation和Weight是有符号INT8；
- 单次乘法产生完整INT16结果；
- PE使用INT32累加器；
- Bias是与累加值同尺度的INT32，并按输出列广播；
- `quant_shift`实现2的幂缩放、就近舍入和INT8饱和；
- ReLU将负数输出变为0；
- Activation、Weight和输出zero-point固定为0。

矩阵总线从低位到高位存放00、01、10、11：

```text
activation_matrix = {A11, A10, A01, A00}
weight_matrix     = {W11, W10, W01, W00}
result_matrix     = {Y11, Y10, Y01, Y00}
bias_vector       = {bias1, bias0}
```

详细规则见[量化说明](docs/quantization.md)和[接口说明](docs/interfaces.md)。

## 模块结构

```text
XingHuo_NPU
├── ControlUnit
├── MatrixFeeder
├── SystolicArray
│   └── MacPE × 4
└── VPU
    ├── Bias × 4
    ├── Requantize × 4
    └── ReLU × 4
```

详细数据流和状态时序见[架构说明](docs/architecture.md)。

## 验证方法

`sim/generate_vectors.py`生成定向和随机输入，并调用`sim/golden_model.py`得到expected。
生成文件位于`build/sim/test_vectors.txt`。C++ testbench只读取向量、驱动DUT并比较
actual，不包含任何手工expected。详见[验证说明](docs/verification.md)。

## PPA评估

本地ICS55流程需要额外安装Yosys、ICsprout55 PDK和包含iSTA/iPA的iEDA。检查依赖：

```bash
make ppa-check \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA
```

运行评估：

```bash
make ppa \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA
```

当前PPA默认目标为300 MHz（约3.333 ns），可以通过`CLK_FREQ_MHZ`覆盖。详细说明见
[`ppa/README.md`](ppa/README.md)。PPA依赖和工艺库不进入公共CI。

## 当前限制

- 固定2×2矩阵规模，没有可编程指令或片上Unified Buffer；
- 输入在一次任务执行期间必须由外部保持稳定；
- 只支持共享的2次幂重量化右移和固定ReLU；
- 没有非零zero-point、逐通道量化、DMA、总线包装或SoC软件栈；
- 基础SDC只约束时钟，封装确定前没有虚构IO delay、驱动和负载。
