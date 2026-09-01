# 架构设计

星火NPU当前是一个2×2 Output Stationary（输出驻留）Systolic Array（脉动阵列）。
一次任务计算：

```text
Y = ReLU(Requantize(A × W + Bias))
```

## 模块关系

```text
XingHuo_NPU
├── ControlUnit       产生清零、阵列步进和结果写回控制
├── MatrixFeeder      按传播距离错开A和W的注入时刻
├── SystolicArray
│   └── MacPE × 4     传播操作数并在本地保存INT32 Partial Sum（部分和）
│       └── Active/Shadow Weight Bank（活动/影子权重存储组，NPU1.2）
├── VPU
│   ├── Bias × 4      按列加INT32 Bias
│   ├── Requantize ×4 右移舍入并饱和为INT8
│   └── ReLU ×4       清零负数
├── Error Monitor     记录重复start和Bias溢出
└── Performance Monitor 记录最近周期数和累计任务数
```

数据通路由`MatrixFeeder → SystolicArray → VPU`组成，控制通路由`ControlUnit`组成。
顶层只连接模块，不重复实现子模块算法。

## 一次运算的时序

控制状态依次为：

```text
IDLE → CLEAR → RUN(phase 0,1,2,3) → WRITE_RESULT → IDLE
```

1. 在`IDLE`且`start=1`的上升沿接受任务，`busy`变为1；
2. `CLEAR`清除四个PE的传播寄存器和Accumulator（累加器）；
3. 四个`RUN`周期逐拍注入数据，并让最后的数据传播到目标PE；
4. `WRITE_RESULT`把VPU结果写入`result_matrix`，同时产生一个周期的`done`；
5. 状态返回`IDLE`，可以接受下一次任务。

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

## NPU1.2 Weight-resident（权重驻留）通路

```text
weight_matrix ──weight_load──→ shadow bank（每个PE）
                                      │
                           空闲时weight_switch
                                      ↓
activation ───────────────→ active bank × MAC ──→ accumulator
```

当前阵列仍采用Output Stationary：一个PE负责一个输出元素，并在四个RUN周期中完成
长度为2的Dot Product（点积）。因此每个PE的一个Weight Bank保存同一输出列的两个
INT8权重。PE00/PE10保存
`W00、W10`，PE01/PE11保存`W01、W11`；行间副本是维持现有6周期数据流的结构代价。

Shadow Register（影子寄存器）可在计算期间装载，MAC只读取Active Register（活动
寄存器）。顶层仅在Core空闲且Shadow Bank有效时向所有PE同时发出切换脉冲，防止
部分PE使用新权重、部分PE使用旧权重。切换完成后，可以用同一Active Weight连续
处理多组Activation。

NPU1.2不再保留Direct Weight Datapath。MatrixFeeder只调度Activation，PE之间也不再
传播Weight；这减少了权重传播寄存器和二选一数据选择逻辑，并使所有合法任务统一遵循
`Load Shadow → Switch Active → Start`协议。
