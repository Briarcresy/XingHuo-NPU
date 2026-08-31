# 顶层接口

顶层模块是`src/XingHuo_NPU.v`中的`XingHuo_NPU`。

| 端口 | 方向 | 位宽 | 含义 |
|---|---|---:|---|
| `clk` | 输入 | 1 | 上升沿时钟 |
| `rst` | 输入 | 1 | 高有效异步复位 |
| `start` | 输入 | 1 | 在空闲状态启动一次任务 |
| `activation_matrix` | 输入 | 32 | 2×2 INT8 Activation |
| `weight_matrix` | 输入 | 32 | 2×2 INT8 Weight |
| `bias_vector` | 输入 | 64 | 两个INT32 Bias |
| `quant_shift` | 输入 | 5 | 0～31位重量化右移量 |
| `busy` | 输出 | 1 | 正在执行任务 |
| `done` | 输出 | 1 | 结果写回完成，保持一个周期 |
| `result_matrix` | 输出 | 32 | 2×2 ReLU后INT8结果 |

## 数据打包

矩阵采用行优先顺序：

```text
bits [7:0]   = element_00
bits [15:8]  = element_01
bits [23:16] = element_10
bits [31:24] = element_11
```

因此总线写作`{element_11, element_10, element_01, element_00}`。每个元素是8位二补码，
虽然顶层扁平总线未声明`signed`，切分后的元素会按有符号INT8解释。

Bias的打包为：

```text
bias_vector[31:0]  = bias_0  // 输出第0列
bias_vector[63:32] = bias_1  // 输出第1列
```

## 握手要求

- 只在`busy=0`时拉高`start`；
- `start`保持一个完整时钟周期即可；
- 当前接口没有输入锁存，任务期间必须保持所有数值输入稳定；
- `done=1`时`result_matrix`已经有效；
- `result_matrix`会保持到下一次结果写回或复位。
