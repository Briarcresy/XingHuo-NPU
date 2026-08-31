# 架构设计

星火NPU当前是一个2×2输出驻留（output-stationary）脉动阵列。一次任务计算：

```text
Y = ReLU(Requantize(A × W + Bias))
```

## 模块关系

```text
XingHuo_NPU
├── ControlUnit       产生清零、阵列步进和结果写回控制
├── MatrixFeeder      按传播距离错开A和W的注入时刻
├── SystolicArray
│   └── MacPE × 4     传播操作数并在本地保存INT32部分和
└── VPU
    ├── Bias × 4      按列加INT32 Bias
    ├── Requantize ×4 右移舍入并饱和为INT8
    └── ReLU ×4       清零负数
```

数据通路由`MatrixFeeder → SystolicArray → VPU`组成，控制通路由`ControlUnit`组成。
顶层只连接模块，不重复实现子模块算法。

## 一次运算的时序

控制状态依次为：

```text
IDLE → CLEAR → RUN(phase 0,1,2,3) → WRITE_RESULT → IDLE
```

1. 在`IDLE`且`start=1`的上升沿接受任务，`busy`变为1；
2. `CLEAR`清除四个PE的传播寄存器和累加器；
3. 四个`RUN`周期逐拍注入数据，并让最后的数据传播到目标PE；
4. `WRITE_RESULT`把VPU结果写入`result_matrix`，同时产生一个周期的`done`；
5. 状态返回`IDLE`，可以接受下一次任务。

输入矩阵、Bias和`quant_shift`应从任务被接受前保持到`done`出现。当前设计没有内部
输入缓冲区，也不支持任务队列。
