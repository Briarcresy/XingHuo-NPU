# 顶层接口

顶层模块是`src/XingHuo_NPU.v`中的`XingHuo_NPU`。

| 端口 | 方向 | 位宽 | 含义 |
|---|---|---:|---|
| `clk` | 输入 | 1 | 上升沿时钟 |
| `rst` | 输入 | 1 | 高有效Asynchronous Reset（异步复位） |
| `start` | 输入 | 1 | 在空闲状态启动一次任务 |
| `clear_error` | 输入 | 1 | 清除Sticky Error（粘滞错误），不中断当前任务 |
| `weight_load` | 输入 | 1 | 把当前`weight_matrix`装入Shadow Weight Bank（影子权重存储组） |
| `weight_switch` | 输入 | 1 | 空闲时执行Atomic Switch（原子切换） |
| `activation_matrix` | 输入 | 32 | 2×2 INT8 Activation |
| `weight_matrix` | 输入 | 32 | `weight_load`写入Shadow Weight Bank的数据源 |
| `bias_vector` | 输入 | 64 | 两个INT32 Bias |
| `quant_shift` | 输入 | 5 | 0～31位重量化右移量 |
| `busy` | 输出 | 1 | 正在执行任务 |
| `done` | 输出 | 1 | 结果写回完成，保持一个周期 |
| `result_matrix` | 输出 | 32 | 2×2 ReLU后INT8结果 |
| `error` | 输出 | 1 | `error_code`任意位非0 |
| `error_code` | 输出 | 8 | NPU1.1/1.2 Sticky Error Code（粘滞错误码） |
| `active_weight_valid` | 输出 | 1 | Active Weight Bank已经准备好 |
| `shadow_weight_valid` | 输出 | 1 | Shadow Weight Bank包含待切换权重 |
| `cycle_count` | 输出 | 16 | 最近一个完成任务的Core周期数 |
| `task_count` | 输出 | 32 | 复位以来累计完成任务数 |

## 错误与可观测性接口

| 位 | 名称 | 置位条件 |
|---:|---|---|
| 0 | `START_WHILE_BUSY` | `busy=1`期间再次采样到`start=1` |
| 1 | `BIAS_OVERFLOW` | 任一路INT32累加值与Bias相加发生二补码溢出 |
| 2 | `WEIGHT_SWITCH_WHILE_BUSY` | 计算期间请求切换active权重，切换被拒绝 |
| 3 | `START_WITHOUT_ACTIVE_WEIGHT` | 驻留模式无有效active权重时启动，任务被拒绝 |
| 4 | `WEIGHT_SWITCH_WITHOUT_SHADOW` | shadow无效时请求切换，切换被拒绝 |
| 7:5 | 保留 | 固定为0 |

错误位是粘滞的：事件消失后仍保持为1，直到`clear_error=1`的时钟沿或`rst=1`。
`clear_error`不清除结果、`cycle_count`或`task_count`，也不会中断正在执行的任务。

Bias溢出只报告数学结果超出INT32范围，不改变NPU1.0的数值规则：实际数据仍保留
加法结果低32位，然后继续重量化和ReLU。当前2×2实现正常任务`cycle_count=6`；
内部当前周期计数饱和于`16'hffff`，`task_count`按32位自然回绕。

## NPU1.2 Weight-resident Protocol（权重驻留协议）

典型操作顺序：

```text
weight_matrix = 第一组权重，weight_load脉冲
    ↓ shadow_weight_valid = 1
空闲时给weight_switch脉冲
    ↓ active_weight_valid = 1，shadow_weight_valid = 0
给start脉冲
    ↓ 多个任务可以复用同一组Active Weight
```

`weight_load`只修改Shadow Bank，因此允许在`busy=1`时装载下一组权重，不影响当前
计算。`weight_switch`只在`busy=0 && shadow_weight_valid=1`时生效，保证四个PE在
同一时钟沿Atomic Update（原子更新）Active Weight。`weight_load`和合法
`weight_switch`可以同拍：旧Shadow进入Active，当前`weight_matrix`同时成为新Shadow。

Core只支持Weight-resident Mode，不再包含Direct Weight Datapath（直接权重数据通路）。
复位后必须先完成至少一次合法的`weight_load`和`weight_switch`，否则`start`会被拒绝并
置位`error_code[3]`。计算期间`weight_matrix`可以变化，MAC只读取PE内Active Bank。

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

## Handshake（握手）要求

- 只在`busy=0`时拉高`start`；
- `busy=1`期间的`start`不会重启任务，但会置位`error_code[0]`；
- `start`保持一个完整时钟周期即可；
- 任务期间必须保持Activation、Bias和`quant_shift`稳定；
- `weight_matrix`只在`weight_load=1`的时钟上升沿被采样，其他时间无需保持；
- `done=1`时`result_matrix`已经有效；
- `result_matrix`会保持到下一次结果写回或复位。
