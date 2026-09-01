# “星火” NPU

星火NPU是一个用于学习、验证和小面积流片迭代的2×2对称INT8推理加速器。当前数据
通路为：

```text
INT8矩阵乘法 → INT32 Accumulation（累加）→ INT32 Bias →
Requantization（重量化）→ INT8 Saturation（饱和）→ ReLU
```

正式RTL严格使用IEEE Verilog-2005；Python Golden Model（黄金参考模型）独立计算
期望结果与Bias Overflow（溢出）状态；C++17 Testbench（测试平台）通过Verilator
批量验证RTL，SVA保存在独立验证目录。

## 当前开发版本：NPU1.2

`NPU1.2`继承NPU1.1的Error Monitor（错误监控）和Performance Counter（性能计数器），
并为每个PE增加Active/Shadow Weight Bank（活动/影子权重存储组）。Core采用纯
Weight-resident Mode（权重驻留模式），支持提前装载、Atomic Switch（原子切换）和
跨任务Weight Reuse（权重复用）。

## 核心指标

| 指标                 | NPU1.0基线        | NPU1.1可观测性版 | NPU1.2权重驻留版       |
| -------------------- | ----------------- | ----------------- | ---------------------- |
| 计算规模             | 2×2 INT8矩阵乘法  | 与NPU1.0相同      | 与NPU1.0相同           |
| PE数量               | 4个               | 4个               | 4个                    |
| 权重模式             | Direct（直接）    | Direct（直接）    | Weight-resident（权重驻留） |
| 可观测性             | `busy`、`done`    | 错误与性能计数    | 增加权重bank状态       |
| PPA目标频率          | 300 MHz           | 100 MHz           | 100 MHz                |
| 映射估算最高频率     | 高于300 MHz       | 约264.486 MHz     | 约261.597 MHz          |
| 单次计算延迟         | 6周期，约20 ns    | 6周期，约60 ns    | 6周期，约60 ns         |
| 连续任务启动间隔     | 7周期，约23.33 ns | 7周期，约70 ns    | 7周期，约70 ns         |
| 100 MHz理论峰值算力  | —                 | 0.4 GMAC/s        | 0.4 GMAC/s             |
| 标准单元数量         | 5376              | 5705              | 5992（比NPU1.1多5.03%） |
| 标准单元面积         | 10999.24 µm²      | 11703.44 µm²      | 12727.68 µm²（多8.75%） |
| 时序单元面积         | 1536.92 µm²       | 2054.36 µm²       | 2469.88 µm²，占19.41%  |
| 建立/保持WNS         | +0.063/+0.140 ns  | +6.219/+0.113 ns  | +6.177/+0.138 ns       |
| 建立/保持TNS         | 0/0 ns            | 0/0 ns            | 0/0 ns                 |
| 粗略功耗估算         | 3.799 W           | 2.026 W           | 1.606 W                |
| 顶层信号位数         | 170位             | 228位             | 232位                  |
| Verilator批量用例    | 1012例            | 1012例            | 1016例及独立SVA        |

NPU1.2在100 MHz下Setup/Hold Check（建立/保持检查）均通过。相比NPU1.1，面积增加
约8.75%；现有Output Stationary（输出驻留）结构要求每个PE保存两个K方向权重，两套
Active/Shadow Bank在四个PE中共增加128位寄存器。砍掉Direct Weight Datapath后，
面积比兼容双模式版本减少约2.30%。功耗没有真实VCD/SAIF，只能作为粗略参考。

PPA数据来自ICS55 RVT、TT、1.2 V、25 ℃条件下的Yosys门级映射和iEDA分析。面积是
标准单元面积，不是最终Die面积；功耗使用统一的0.1默认翻转率且没有真实VCD/SAIF、
布局布线和寄生参数，只适合比较不同RTL版本，不能作为最终芯片功耗。

## 版本历史

- `NPU1.0`：完成2×2 INT8推理数据通路和基础验证；
- `NPU1.1`：增加Sticky Error（粘滞错误）、Bias Overflow、Performance Counter和SVA；
- `NPU1.2`：采用纯Weight-resident Mode，增加Active/Shadow Weight Bank、Atomic Switch
  和Weight Reuse。

## 目录结构

```text
src/          正式Verilog-2005 RTL
sim/          Python golden model、向量生成器和Verilator C++ testbench
tests/        Python golden model单元测试
filelists/    统一RTL文件列表
constraints/  基础时钟约束
docs/         架构、接口、量化和验证文档
verification/ 独立SystemVerilog Assertions，不进入正式综合
ppa/          Yosys、ICS55与iEDA PPA评估流程
tapeout/      各流片平台的独立适配版本，不影响通用Core主线
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

运行NPU1.2周期级断言：

```bash
make sva-test
```

默认生成16个定向用例和1000个固定种子随机用例。成功结果为：

```text
ALL 1016 TESTS PASSED
directed=16 random=1000 seed=0x20260831
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
- PE使用INT32 Accumulator（累加器）；
- Bias是与累加值同尺度的INT32，并按输出列广播；
- `quant_shift`实现2的幂缩放、Round-to-nearest（就近舍入）和INT8 Saturation；
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
│   └── MacPE × 4（每个PE含active/shadow权重bank）
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

当前PPA默认目标为100 MHz（10 ns），可以通过`CLK_FREQ_MHZ`覆盖。详细说明见
[`ppa/README.md`](ppa/README.md)。PPA依赖和工艺库不进入公共CI。

## 当前限制

- 固定2×2矩阵规模，没有可编程指令或片上Unified Buffer；
- 任务期间只需保持Activation、Bias和量化配置；Weight由PE内Active Bank提供；
- 只支持共享的2次幂Requantization右移和固定ReLU；
- 没有非零zero-point、逐通道量化、DMA、总线包装或SoC软件栈；
- 基础SDC只约束时钟，封装确定前没有虚构IO delay、驱动和负载。
