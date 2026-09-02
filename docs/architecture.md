# 架构设计

星火NPU当前是一个2×2 True Weight Stationary（真正的权重固定）Systolic Array（脉动阵列）。
一次任务计算：

```text
Y = ReLU(Requantize(A × W + Bias))
```

## 模块关系

```text
XingHuo_NPU
├── ControlUnit       产生清零、阵列步进和结果写回控制
├── MatrixFeeder      对两个K列的Activation进行Skew（错拍）
├── SystolicArray
│   └── MacPE × 4     固定Weight，纵传Activation，横传INT32 Partial Sum
│       └── 每个PE各一个Active/Shadow Weight
├── ResultCollector   收集阵列右边界分周期到达的四个结果
├── VPU
│   ├── Bias × 4      按列加INT32 Bias
│   ├── Requantize ×4 直接算术右移并饱和为INT8
│   └── ReLU ×4       清零负数
├── Error Monitor     记录重复start和Bias溢出
└── Performance Monitor 记录最近周期数和累计任务数
```

数据通路由`MatrixFeeder → SystolicArray → ResultCollector → VPU`组成，控制通路由
`ControlUnit`组成。
顶层只连接模块，不重复实现子模块算法。

## 一次运算的时序

控制状态依次为：

```text
IDLE → CLEAR → RUN(phase 0,1,2,3) → COLLECT → WRITE_RESULT → IDLE
```

1. 在`IDLE`且`start=1`的上升沿接受任务，`busy`变为1；
2. `CLEAR`清除Activation、Partial Sum和Result Collector状态，但保留权重Bank；
3. 四个`RUN`周期注入两行Activation并排空Systolic Pipeline（脉动流水线）；
4. `COLLECT`让Result Collector锁存最后一个边界结果；
5. `WRITE_RESULT`把VPU结果写入`result_matrix`，同时产生一个周期的`done`；
6. 状态返回`IDLE`，可以接受下一次任务。

Weight始终来自PE内部Active Bank。Activation、Bias和`quant_shift`应从任务被接受前
保持到`done`出现；`weight_matrix`只在`weight_load`时被采样。当前设计没有完整输入
缓冲区，也不支持任务队列。

## NPU1.1可观测性通路

```text
start + busy ───────────────→ START_WHILE_BUSY Sticky Bit（粘滞位）
Bias四路加法Overflow（溢出）→ BIAS_OVERFLOW Sticky Bit
busy + done ────────────────→ cycle_count / task_count
```

`Bias`模块同时输出32位回绕结果和溢出标志，VPU将四路标志归约后交给顶层。错误
监控不会修改数据结果或控制状态机，因此NPU1.1与NPU1.0的合法任务数值行为一致。

## NPU1.2 True Weight Stationary数据流

```text
                  K=0                         K=1
输出列j=0   PE00: W00 ──Partial Sum──→ PE01: W10 ──→ C[i][0]
                │Activation                 │Activation
                ↓                           ↓
输出列j=1   PE10: W01 ──Partial Sum──→ PE11: W11 ──→ C[i][1]
```

阵列行对应输出列`j`，阵列列对应归约维度`k`。每个PE固定一个`W[k][j]`，所以四个PE
恰好保存四个不同权重，不再存在权重副本。每个PE具有一个Active和一个Shadow寄存器，
权重Bank总容量为`4 × 2 × 8 = 64 bit`。

Activation按输入矩阵的行依次进入阵列顶部，并沿阵列列向下传播；Partial Sum从每行
左侧的0开始，经过两个PE向右传播。右边界依次产生`C00/C10`和`C01/C11`，
Result Collector根据Valid信号将它们恢复为`sum00/sum01/sum10/sum11`。

Shadow Register可在计算期间装载，MAC只读取Active Register。顶层仅在Core空闲且
Shadow Bank有效时向所有PE同时发出切换脉冲。所有合法任务统一遵循
`Load Shadow → Switch Active → Start`协议。

与旧Output Stationary版本相比，True Weight Stationary减少了重复权重和本地累加
组合逻辑，但需要在PE间传输32位Partial Sum，并增加Result Collector。当前固定任务
接口下延迟为7周期、连续启动间隔为8周期；未来改成Streaming valid/ready后，可以
进一步利用阵列流水能力。
