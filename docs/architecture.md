# 架构说明

设计分成可复用的 NPU Core 和 MPSoC-Digital Tile Adapter（Tile 适配层）。Core 不知道按钮、LED、外部命令和 Shared RAM；适配层负责把平台资源变成 Core 任务。

```text
io_btn/io_dip -> ButtonConditioner -> ManualInputController --+
                                                             |
io_customIn -> ExternalHostInterface -------------------------+-> RAM Arbiter
                                                                    |
SoC Shared RAM <----------------------------------------------------+
       |
       +-> XorNetworkController -> XingHuo_NPU Core
                    |                    |
                    +<--- results -------+
                    |
                    +-> DisplayController -> LED / seven-segment
```

`XorNetworkController`是两层网络 Sequencer（时序控制器）。它读取输入和第一层 Weight/Bias/Shift，把权重装入 Shadow Bank（影子权重组）并切换为 Active Bank（活动权重组），启动 Core，收集 Hidden Activation（隐藏层激活）；随后以隐藏层结果作为第二层输入，重复流程并写回输出、类别、状态和错误码。

Core 内部由 `MatrixFeeder`、2×2 `SystolicArray`、`ResultCollector`、`Bias`、`Requantize`、`ReLU` 与 `ControlUnit` 组成。PE 的权重保持在本地寄存器中，Activation（激活值）横向传播，Partial Sum（部分和）纵向传播。

Shared RAM 是平台资源：256×8、异步读、时钟上升沿写。网络运行期间 Sequencer 独占 RAM；空闲时 RAM 交给当前输入模式。模式只在空闲且无写脉冲时改变。

Tile 与 Core 状态均在 `clock` 上升沿使用同步高有效 `reset`。异步按钮和 `io_customIn` 在消费前经过两级 Synchronizer（同步器）；多位外部命令采用“数据稳定到应答”的约束。
