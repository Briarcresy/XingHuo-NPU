# Tile RTL 学习导读

这份导读把当前 Tile 中的真实代码与常见数字系统设计方法对应起来。阅读顺序从芯片边界到计算核心，适合同时打开 RTL 和仿真波形。

参考讲义：

- [一生一芯 C4：总线](https://ysyx.oscc.cc/docs/2607/c/4.html)
- [一生一芯 C5：SoC 计算机系统](https://ysyx.oscc.cc/docs/2607/c/5.html)

## 1. 先看 package：把协议定义从实现中抽出来

从 `rtl/tile/TileTypesPkg.sv` 开始。它集中定义主机 Opcode、显示页、网络状态和 Shared RAM 地址。SystemVerilog `package` 类似软件工程中的公共类型模块，避免多个模块各自复制魔数。

重点观察：

- `typedef enum logic [...]` 同时给出类型、位宽和合法编码；
- `network_state_t state` 比 `logic [4:0] state` 更容易在波形中识别；
- package 必须在使用它的模块之前编译，所以它位于 `filelists/tile.f` 前部。

## 2. 看芯片边界：CDC 与功能逻辑分层

阅读 `TileInputSynchronizer.sv` 和 `ButtonConditioner.sv`。

按钮、拨码和 `customIn` 不保证与 Tile 时钟同相，先经过两级同步器。`ASYNC_REG` 属性告诉综合与布局工具这些寄存器属于亚稳态同步链。按钮同步后再去抖，体现“CDC 处理”和“业务处理”分开的模块边界。

三组输入的同步链分别使用独立时序块。按钮去抖内部也把候选计时、稳定电平更新和单周期按下事件分开，使每组寄存器只有一个清晰职责。

多位总线不能只靠逐位两级同步保证原子性。`customIn` 额外使用 Toggle Handshake：发送端先稳定 Opcode/Payload，再翻转 Request，并保持数据直到 ACK。这里可以对照讲义中的总线协议：协议不只是连线，还包含双方必须遵守的时序约定。

波形练习：让 `buttons_async` 在时钟边沿附近变化，观察 `buttons_sync` 最早两拍后变化；再观察 `candidate` 连续稳定到计数完成时，`buttons_stable` 才更新。

## 3. 看握手：valid、ready 与 fire

阅读 `ExternalHostInterface.sv`：

```systemverilog
command_valid = request_toggle != acknowledge_toggle;
command_ready = enable && !network_busy && !write_pending;
command_fire  = command_valid && command_ready;
```

这正是讲义中的解耦握手规则。只有 `fire` 为 1，接收端才消费一次命令。`valid=1, ready=0` 时，外部协议要求 Request、Opcode 和 Payload 保持不变，因此忙时不会丢命令。

写命令比普通命令多一个 `write_pending` 周期。原因是 `ram_write_request` 在寄存器上升沿产生，而 Shared RAM 在后续上升沿采样它；ACK 必须等 RAM 真正完成采样后返回。这对应系统总线中“请求被接受”和“事务完成”是两个不同事件。

波形练习：在 `network_busy=1` 时翻转 Request，确认 `command_valid` 保持、ACK 不变；busy 结束后只出现一次 `command_fire`。

## 4. 看仲裁：一个端口如何服务多个主设备

阅读 `XingHuoNpuTile.sv` 中的 `controller_ram_grant`、`host_ram_grant` 和 Shared RAM 组合逻辑。

三个 RAM 使用者共享一个物理端口，固定优先级为：

1. 网络控制器；
2. 外部主机；
3. 手动控制器。

网络运行时必须连续取得端口，否则控制器当前状态所给出的地址会被其他主设备覆盖。命名 grant 信号把仲裁策略与数据多路选择分开，便于在波形中确认“谁获得资源”。`mode_handoff_ready` 则保证旧模式已经产生的单周期事件被消费后才切换所有权。

这是一生一芯 C4 中总线仲裁思想的缩小版本。当前只有一个从设备，因此不需要 AXI Crossbar 的地址译码和多从设备响应选择。

## 5. 看状态机：控制通路与数据通路

阅读 `XorNetworkController.sv`。`network_state_t` 状态机是控制通路，`activation_matrix`、`weight_matrix`、`bias_vector` 和结果寄存器是数据通路。

按以下四段看状态转移：

1. 从 RAM 装载第一层参数；
2. 装权重、启动 Core、等待 `core_done`；
3. 写回隐藏层并为第二层重复上述过程；
4. 写回最终结果、类别、状态和错误码。

组合块只译码当前状态，给出 RAM 地址、写使能和 Core 控制信号；时序块只在上升沿保存状态和数据。这种写法便于静态时序分析，也能避免组合环路和意外锁存器。

波形练习：同时显示 `state`、`byte_index`、`ram_address`、`ram_write_enable`、`core_start`、`core_busy` 和 `core_done`，逐拍画出一次可编程任务的事务表。

## 6. 看组合译码：默认赋值与完整覆盖

阅读 `DisplayController.sv`。组合块开头先给所有输出默认值，`case` 分支只覆盖该页面需要改变的字段。`default` 负责非法页面的安全显示。

这里的开头默认值不是重复代码：它保证每条组合路径都有赋值，从而避免综合出锁存器。页面名来自 package，波形和代码中无需记忆 0～10 的裸数字含义。

## 7. 为什么当前不把 Tile 外口改成 AXI

AXI4-Lite 适合片上、同一同步系统中的内存映射控制访问，但 MPSoC-Digital 已固定 Tile 的顶层端口和 Shared RAM 接口。自行增加 AXI 顶层端口会违反平台契约，也不能自动获得 SoC 的 AXI 互联。

当前设计保留平台端口，在内部学习并使用 AXI 同源的设计原则：

- 用 `valid && ready` 定义唯一传输事件；
- backpressure 期间保持请求；
- 明确区分请求接受和写完成；
- 用 grant 表达多主设备仲裁；
- 用寄存器映射组织控制、状态和数据。

如果以后平台提供 AXI/APB 从设备接口，适合新增一个独立 Adapter，把总线事务转换成当前的 RAM、Start 和 Status 操作。网络控制器和 NPU Core 无需随总线协议重写。
