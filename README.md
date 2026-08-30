# “星火” NPU

星火NPU是一个用于学习和小面积流片的2×2对称INT8推理加速器。当前完成：

```text
INT8矩阵乘法 → INT32累加 → INT32 Bias → 重量化 → INT8饱和 → ReLU
```

## 数值格式

- Activation和Weight使用8位二补码INT8，范围为-128～127；
- 乘法产生完整的INT16结果，不提前截断；
- PE使用INT32累加器，避免短矩阵乘法中的累加溢出；
- Bias使用INT32，并且必须与累加器使用相同尺度；
- 输出经过舍入、饱和后成为INT8，ReLU将负数变为0。

本设计采用对称量化，所以Activation、Weight和输出的zero-point都固定为0。软件侧
应按照下面的方式生成Bias整数：

```text
bias_int32 = round(real_bias / (activation_scale * weight_scale))
```

完整INT8重量化通常需要乘法系数。本设计为了节省面积，暂时只支持2的幂缩放：

```text
output_int8 = saturate(round(accumulator / 2^quant_shift))
```

`quant_shift=0`表示不缩放，`quant_shift=1`表示除以2，以此类推。一层的四个输出
共用同一个`quant_shift`。这适合教学和第一版流片，以后可以升级为每通道乘数和移位。

## 顶层接口

顶层模块为`XingHuo_NPU`，位于`src/XingHuo_NPU.v`。

矩阵总线都采用行优先顺序，从低位到高位依次存放00、01、10、11元素：

```text
activation_matrix = {A11, A10, A01, A00}
weight_matrix     = {W11, W10, W01, W00}
result_matrix     = {Y11, Y10, Y01, Y00}
```

每个A、W和Y元素占8位。`bias_vector`包含两个INT32 Bias：

```text
bias_vector = {bias1, bias0}
```

其中`bias0`用于输出第0列，`bias1`用于输出第1列。

## 模块结构

```text
XingHuo_NPU
├── ControlUnit       控制CLEAR、RUN和结果写回
├── MatrixFeeder      按脉动阵列时序错开输入数据
├── SystolicArray     2×2输出驻留脉动阵列
│   └── MacPE × 4     INT8乘法和INT32累加
└── VPU
    ├── Bias × 4      加INT32 Bias
    ├── Requantize ×4 舍入、右移并饱和到INT8
    └── ReLU ×4       将负数钳位为0
```

## 行为仿真

自检testbench位于`tb/XingHuo_NPU_tb.v`。运行：

```bash
mkdir -p build/sim
iverilog -g2005 -Wall -s XingHuo_NPU_tb \
  -o build/sim/xinghuo_npu_tb.vvp src/*.v tb/XingHuo_NPU_tb.v
vvp build/sim/xinghuo_npu_tb.vvp
```

正确结果应包含：

```text
PASS: basic_int8_matmul
PASS: requantize_shift
PASS: relu_negative_to_zero
ALL TESTS PASSED
```

运行Verilator lint：

```bash
verilator --lint-only -Wall --language 1364-2005 --top-module XingHuo_NPU src/*.v
```

## PPA评估

详细方法见`ppa/README.md`。综合和时序分析只读取`src/`下的正式RTL，生成物保存在
`build/ppa/`，不会提交到Git。
