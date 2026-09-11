# RTL 模块接口说明

本文按当前 RTL 源码记录每个模块的端口含义和时序语义。除特别说明外，时序模块均在 `clock/clk` 上升沿工作，`reset/rst` 为同步高有效复位；组合模块没有时钟和内部状态。

数据约定：INT8 和 INT32 均使用二补码。2×2 矩阵按照 `{x11, x10, x01, x00}` 打包，即 `[7:0]=x00`、`[15:8]=x01`、`[23:16]=x10`、`[31:24]=x11`。控制脉冲应保持一个完整时钟周期，除非对应条目明确写为保持电平。

## Tile 层模块

### `TileTypesPkg`

Tile 层公共 SystemVerilog package。它集中定义 Opcode、显示页面、网络状态和 Shared RAM 地址常量。package 不生成硬件；当前综合工具只允许部分使用点采用枚举类型，因此控制器寄存器保留显式位宽，但所有协议值仍使用集中定义的名称，避免散落裸数字。

### `XingHuoNpuTile`

MPSoC-Digital 用户设计顶层。它同步外部输入、选择手动或主机控制源、仲裁 Shared RAM，并连接两层网络控制器和显示逻辑。参数 `BUTTON_DEBOUNCE_CYCLES` 设置按钮状态连续稳定多少个周期后才被接受，默认在 150 MHz 下约为 10 ms。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clock` | 输入 1 bit | Tile 工作时钟，所有时序逻辑使用其上升沿。 |
| `reset` | 输入 1 bit | 同步高有效复位；复位采样沿强制屏蔽 `io_ramWen`。 |
| `io_led` | 输出 8 bit | 当前显示页的 LED 数据。 |
| `io_ledUpdate` | 输出 1 bit | LED 更新有效，当前实现持续为 1。 |
| `io_btn` | 输入 8 bit | 异步按钮输入，先经过两级同步，再去抖。 |
| `io_dip` | 输入 8 bit | 异步 DIP 输入，先经过两级同步；使用者应在按键操作前使其稳定。 |
| `io_hex7seg_0` | 输出 4 bit | 低位十六进制数字，不是七段段码。 |
| `io_hex7seg_1` | 输出 4 bit | 高位十六进制数字，不是七段段码。 |
| `io_hex7segUpdate` | 输出 1 bit | 数码管更新有效，当前实现持续为 1。 |
| `io_customOut` | 输出 16 bit | 主机响应和状态总线，位定义见下表。 |
| `io_customIn` | 输入 16 bit | 异步主机命令总线，先经过两级同步，并使用 Toggle Handshake。 |
| `io_ramAddr` | 输出 8 bit | 256×8 Shared RAM 地址。网络忙时由网络控制器独占。 |
| `io_ramWen` | 输出 1 bit | Shared RAM 写使能，在上升沿为 1 时写入。 |
| `io_ramWdata` | 输出 8 bit | Shared RAM 写数据。 |
| `io_ramRdata` | 输入 8 bit | 当前 `io_ramAddr` 对应的异步组合读数据，不经过 CDC 同步器。 |

`io_customOut` 位定义：

| 位 | 含义 |
|---:|---|
| `[7:0]` | 外部主机最近一次 `READ_NEXT` 读到的数据。 |
| `[8]` | Acknowledge Toggle；与请求 Toggle 相等表示当前请求已完成。 |
| `[9]` | 两层网络 `busy`。 |
| `[10]` | 两层网络粘滞 `done`。 |
| `[11]` | NPU Core 当前 `busy`。 |
| `[12]` | 两层网络粘滞 `error`。 |
| `[13]` | 分类结果。 |
| `[14]` | 已实际切换完成的外部模式状态。 |
| `[15]` | 外部命令协议版本标志，当前固定为 1。 |

### `TileInputSynchronizer`

集中处理 Tile 边界的异步数字输入。每组信号使用 `meta -> sync` 两级寄存器，并用 `ASYNC_REG` 标记。多位总线的各位仍可能在不同采样沿稳定，因此 DIP 依赖人工稳定窗口，`customIn` 依赖握手协议保证整笔命令一致。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clock` | 输入 1 bit | 目标时钟域时钟。 |
| `reset` | 输入 1 bit | 同步高有效复位，将全部同步级清零。 |
| `buttons_async` | 输入 8 bit | 未同步按钮电平。 |
| `dip_async` | 输入 8 bit | 未同步 DIP 电平。 |
| `custom_in_async` | 输入 16 bit | 未同步主机命令总线。 |
| `buttons_sync` | 输出 8 bit | 进入 `clock` 域后的按钮电平。 |
| `dip_sync` | 输出 8 bit | 进入 `clock` 域后的 DIP 电平。 |
| `custom_in_sync` | 输出 16 bit | 进入 `clock` 域后的主机命令总线。 |

### `ButtonConditioner`

对已同步的八位按钮向量去抖，并产生确认按下事件。八个按钮共用一个稳定计数器；任意位改变都会更新整个 `candidate` 并重新计时。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clock` | 输入 1 bit | 工作时钟。 |
| `reset` | 输入 1 bit | 同步高有效复位。 |
| `buttons_sync` | 输入 8 bit | 已同步的当前按钮电平。 |
| `buttons_stable` | 输出 8 bit | 经过去抖确认的保持电平；按下为 1，松开为 0。 |
| `button_pressed` | 输出 8 bit | 对应按钮被确认从 0 变为 1 时产生的单周期脉冲。确认松开不产生脉冲。 |

参数 `DEBOUNCE_CYCLES` 是确认新按钮向量所需的连续稳定周期数。

### `ManualInputController`

把同步后的 DIP 数据和去抖按钮事件转换成 RAM 操作、运行命令和显示翻页操作。`enable=0` 或 `network_busy=1` 时不接受新的按钮命令。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clock` | 输入 1 bit | 工作时钟。 |
| `reset` | 输入 1 bit | 同步高有效复位，将地址和页面清零。 |
| `enable` | 输入 1 bit | 手动模式命令接收使能。 |
| `network_busy` | 输入 1 bit | 网络忙标志；为 1 时阻止手动操作。 |
| `dip_value` | 输入 8 bit | 已同步 DIP 值，作为写数据、地址或 Demo 输入。 |
| `button_pressed` | 输入 8 bit | 八个按钮的单周期确认按下脉冲。 |
| `ram_address` | 输出 8 bit | 当前 RAM 地址；写脉冲期间保持被接受操作的旧地址。 |
| `ram_write_request` | 输出 1 bit | BTN0 触发的单周期 RAM 写请求。 |
| `ram_write_data` | 输出 8 bit | 与写请求配套的锁存 DIP 数据。 |
| `start_programmable` | 输出 1 bit | BTN3 触发的单周期可编程网络启动脉冲。 |
| `start_demo` | 输出 1 bit | BTN7 触发的单周期固定参数 Demo 启动脉冲。 |
| `demo_input` | 输出 2 bit | BTN7 被接受时锁存的 `dip_value[1:0]`。 |
| `clear_status` | 输出 1 bit | BTN6 触发的单周期状态清除脉冲。 |
| `display_page` | 输出 4 bit | BTN4/BTN5 控制的页面号，循环范围为 0～10。 |

按钮定义：BTN0 写字节并递增地址；BTN1 地址归零；BTN2 从 DIP 装载地址；BTN3 启动可编程任务；BTN4/5 前后翻页；BTN6 清状态；BTN7 启动 Demo。

### `ExternalHostInterface`

解析同步后的 `customIn`，用请求/应答 Toggle 一次处理一条命令。主机必须先稳定模式、Opcode 和 Payload 至少 3T，再翻转请求，并保持整条总线到 ACK 完成。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clock` | 输入 1 bit | 工作时钟。 |
| `reset` | 输入 1 bit | 同步高有效复位；ACK、地址和待处理状态清零。 |
| `enable` | 输入 1 bit | 外部模式已交接完成且仍被请求时为 1。 |
| `network_busy` | 输入 1 bit | 为 1 时请求保持待处理，不执行也不应答。 |
| `custom_in_sync` | 输入 16 bit | 已同步主机总线：`[15]` 模式、`[11:9]` Opcode、`[8]` Request Toggle、`[7:0]` Payload。 |
| `ram_read_data` | 输入 8 bit | 当前 `ram_address` 对应的异步 RAM 数据。 |
| `external_mode_request` | 输出 1 bit | 同步后的 `custom_in_sync[15]` 模式请求电平。 |
| `ram_address` | 输出 8 bit | 主机地址指针；写请求期间输出锁存的写地址。 |
| `ram_write_request` | 输出 1 bit | `WRITE_BYTE` 产生的单周期写请求。 |
| `ram_write_data` | 输出 8 bit | `WRITE_BYTE` 锁存的 Payload。 |
| `start_programmable` | 输出 1 bit | `START` 产生的单周期脉冲。 |
| `start_demo` | 输出 1 bit | `START_DEMO` 产生的单周期脉冲。 |
| `demo_input` | 输出 2 bit | `START_DEMO` 接受时锁存的 Payload 低2位。 |
| `clear_status` | 输出 1 bit | `CLEAR` 产生的单周期脉冲。 |
| `read_data` | 输出 8 bit | `READ_NEXT` 执行时锁存的 RAM 数据。 |
| `acknowledge_toggle` | 输出 1 bit | 已完成请求的 Toggle；写命令在 RAM 采样写请求后的下一拍更新。 |

Opcode：0 设置地址，1 写字节并递增地址，2 读字节并递增地址，3 启动可编程任务，4 启动 Demo，5 清状态，6～7 仅应答。

### `XorNetworkController`

顺序调度两次独立 `XingHuo_NPU` 任务。控制器不再包含 Core实例；它通过 `core_*` 命令、数据和响应端口与顶层并列的 Core通信。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clock` | 输入 1 bit | 工作时钟。 |
| `reset` | 输入 1 bit | 同步高有效复位，回到空闲并清除可见状态。 |
| `start_programmable` | 输入 1 bit | 空闲时采样的单周期启动脉冲，从 RAM 读取完整任务。 |
| `start_demo` | 输入 1 bit | 空闲时采样的单周期 Demo 启动脉冲；优先于同时到达的可编程启动。 |
| `demo_input` | 输入 2 bit | Demo 启动时使用的 XOR 输入。 |
| `clear_status` | 输入 1 bit | 空闲时清除粘滞 `done/error`，同时清除 Core 错误。 |
| `ram_address` | 输出 8 bit | 当前状态需要访问的 Shared RAM 地址。 |
| `ram_write_enable` | 输出 1 bit | 结果写回状态中的 RAM 写使能。 |
| `ram_write_data` | 输出 8 bit | 当前结果、分类、状态或错误字节。 |
| `ram_read_data` | 输入 8 bit | `ram_address` 对应的异步组合读数据，在装载状态的上升沿采样。 |
| `busy` | 输出 1 bit | 状态机不在 IDLE 时保持为 1，并取得 RAM 独占权。 |
| `done` | 输出 1 bit | 完整两层任务结束后置 1并保持，直到新任务或清状态。 |
| `error` | 输出 1 bit | 本次任务观察到 Core 错误后置 1并保持。 |
| `classification` | 输出 1 bit | 第二层结果字节1大于字节0时为 1，否则为 0。 |
| `hidden_result` | 输出 32 bit | 第一层四个 INT8 输出，按矩阵约定打包并写至 RAM `0x20～0x23`。 |
| `final_result` | 输出 32 bit | 第二层四个 INT8 输出，写至 RAM `0x40～0x43`。 |
| `core_start_valid/core_start_ready` | 输出/输入，各1 bit | 任务请求通道；控制器保持valid，直到ready握手。 |
| `core_weight_valid/core_weight_ready` | 输出/输入，各1 bit | 权重请求通道；控制器保持valid和权重payload，直到ready握手。 |
| `core_clear_error` | 输出1 bit | 清除独立Core粘滞错误。 |
| `core_activation_matrix/core_weight_matrix` | 输出，各32 bit | 当前层发给 Core 的激活和权重矩阵。 |
| `core_bias_vector/core_quant_shift` | 输出64/5 bit | 当前层发给 Core 的偏置和重量化参数。 |
| `core_busy/core_error` | 输入，各1 bit | 独立 Core 返回的占用和错误状态。 |
| `core_result_valid/core_result_ready` | 输入/输出，各1 bit | 结果响应通道；控制器在等待状态持续ready并在握手沿锁存结果。 |
| `core_result/core_error_code` | 输入32/5 bit | 独立 Core 返回的结果和错误码。 |

### Tile结构辅助模块

- `TileModeController`：等待旧事务结束后安全切换手动/主机模式，并产生两侧使能。
- `TileCommandMux`：根据实际模式选择一组网络启动、Demo输入和清状态命令。
- `TileRamArbiter`：在网络、主机和手动RAM端口之间执行固定优先级仲裁，并在复位时禁止写。
- `TileOutputAdapter`：把显示值、主机ACK和网络/Core状态打包到固定Tile输出端口。

这些模块使`XingHuoNpuTile`只保留实例化与连线，不包含行为过程块。

### `DisplayController`

纯组合显示译码器，不保存状态。`display_page` 选择 LED 内容；两个十六进制输出显示页号、地址或分类。

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| `external_mode` | 输入 1 bit | 当前实际模式，显示在页面0的 LED5。 |
| `display_page` | 输入 4 bit | 页面选择，正常范围0～10。 |
| `manual_address` | 输入 8 bit | 页面1显示的当前手动 RAM 地址。 |
| `current_ram_data` | 输入 8 bit | 页面1通过 LED 显示的当前 RAM 数据。 |
| `network_busy` | 输入 1 bit | 页面0状态位。 |
| `core_busy` | 输入 1 bit | 页面0状态位。 |
| `done` | 输入 1 bit | 页面0状态位。 |
| `error` | 输入 1 bit | 页面0状态位。 |
| `classification` | 输入 1 bit | 页面0和页面10显示的分类结果。 |
| `hidden_result` | 输入 32 bit | 页面2～5逐字节显示的第一层结果。 |
| `final_result` | 输入 32 bit | 页面6～9逐字节显示的第二层结果。 |
| `led_value` | 输出 8 bit | 当前页的 LED 数据。 |
| `hex_low` | 输出 4 bit | 低位十六进制数字。 |
| `hex_high` | 输出 4 bit | 高位十六进制数字。 |

页面0显示状态；页面1数码管显示 RAM 地址、LED显示数据；页面2～5显示隐藏层四字节；页面6～9显示最终层四字节；页面10显示 `C0/C1`。

## Core 层模块

### `XingHuo_NPU`

2×2 INT8 推理 Core 顶层，计算 `ReLU(Requantize(A × W + bias))`。权重单 Bank 驻留在四个 PE 中；一次任务开始前必须至少成功装载一次权重。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clk` | 输入 1 bit | Core 工作时钟。 |
| `rst` | 输入 1 bit | 同步高有效复位。 |
| `start_valid` | 输入 1 bit | 任务请求有效；在握手前必须保持为1，payload同时保持稳定。 |
| `start_ready` | 输出 1 bit | Core可接收任务；条件为当前空闲、没有待消费结果且权重已装载。`start_valid && start_ready` 的上升沿接受任务。 |
| `clear_error` | 输入 1 bit | 清除粘滞错误，不影响当前任务、结果和性能计数。 |
| `weight_valid` | 输入 1 bit | 权重请求有效；在握手前保持为1，并保持 `weight_matrix` 稳定。 |
| `weight_ready` | 输出 1 bit | Core可更新权重；`weight_valid && weight_ready` 的上升沿把完整矩阵装入四个 PE。 |
| `activation_matrix` | 输入 32 bit | 2×2 INT8 激活矩阵，按通用矩阵约定打包；任务执行期间保持稳定。 |
| `weight_matrix` | 输入 32 bit | 2×2 INT8 权重矩阵，在权重通道握手沿采样。 |
| `bias_vector` | 输入 64 bit | `[31:0]=bias0`、`[63:32]=bias1`，分别按输出列广播；任务完成写结果时使用。 |
| `quant_shift` | 输入 5 bit | 四路共用的算术右移量0～31；任务完成写结果时使用。 |
| `busy` | 输出 1 bit | 从接受启动到结果被下游消费期间为1。 |
| `result_valid` | 输出 1 bit | `result_matrix` 有效；下游未就绪时持续保持。 |
| `result_ready` | 输入 1 bit | 下游接收能力；`result_valid && result_ready` 的上升沿消费结果。 |
| `result_matrix` | 输出 32 bit | 四个 ReLU 后 INT8 结果；`result_valid && !result_ready` 时保持稳定。 |
| `error` | 输出 1 bit | `error_code` 任一有效位为1时保持为1。 |
| `error_code` | 输出 5 bit | 粘滞错误：bit1 Bias溢出，bit3无权重启动；bit0/2/4保留0。valid可以先于ready拉高，因此等待ready不属于错误。 |
| `weights_loaded` | 输出 1 bit | 复位后为0，首次成功装载权重后保持为1。 |
| `cycle_count` | 输出 16 bit | 最近成功任务从接受启动到完成的 Core 工作周期数。 |
| `task_count` | 输出 32 bit | 复位以来成功完成任务数量，自然回绕。 |

### `CoreController`

Core控制平面。它接收外部启动、权重与结果握手，管理权重有效位、结果有效位、
粘滞错误和性能计数，并实例化`ComputeSequencer`产生数据通路控制信号。该模块使
`XingHuo_NPU`顶层只承担模块连接，不改变原有接口或周期行为。

| 接口组 | 含义 |
|---|---|
| `start_valid/start_ready` | 接受一次矩阵任务。 |
| `weight_valid/weight_ready/weight_load` | 接受完整权重矩阵，并向阵列产生单拍装载事件。 |
| `result_valid/result_ready` | 保存并消费VPU结果；等待期间保持Core busy。 |
| `phase/array_clear/array_step/result_write_enable` | 送往数据通路的执行控制。 |
| `bias_overflow/error/error_code` | 捕获并保持错误状态。 |
| `weights_loaded/cycle_count/task_count` | 权重与性能可观测状态。 |

### `ComputeSequencer`

Core 控制状态机：`IDLE -> CLEAR -> RUN(phase 0..3) -> COLLECT -> WRITE_RESULT -> IDLE`。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clk` | 输入 1 bit | 工作时钟。 |
| `rst` | 输入 1 bit | 同步高有效复位。 |
| `start` | 输入 1 bit | IDLE 状态接受的启动请求。 |
| `busy` | 输出 1 bit | 任务执行期间保持为1。 |
| `done` | 输出 1 bit | `WRITE_RESULT` 状态产生的单周期完成脉冲。 |
| `phase` | 输出 2 bit | RUN 阶段的0～3拍，驱动激活错拍和流水排空。 |
| `array_clear` | 输出 1 bit | CLEAR 状态电平，清空阵列流水数据和结果收集器。 |
| `array_step` | 输出 1 bit | RUN 状态电平，使能所有 PE 前进一步。 |
| `result_write_enable` | 输出 1 bit | WRITE_RESULT 状态电平，使 VPU 锁存最终 INT8 矩阵。 |

### `MatrixFeeder`

纯组合激活错拍器。根据 `phase` 将 A 的两列按不同拍注入阵列，使激活与横向部分和在各 PE 对齐。

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| `phase` | 输入 2 bit | 0送A00；1送A10和A01；2送A11；3只排空流水。 |
| `activation_matrix` | 输入 32 bit | 打包的2×2 INT8激活矩阵。 |
| `activation_top_col0` | 输出 signed 8 bit | 注入阵列第一个归约位置的激活流。 |
| `activation_top_col1` | 输出 signed 8 bit | 延迟一拍注入第二个归约位置的激活流。 |
| `activation_valid_col0` | 输出 1 bit | `activation_top_col0` 有效。 |
| `activation_valid_col1` | 输出 1 bit | `activation_top_col1` 有效。 |

### `SystolicArray`

由四个 `MacPE` 组成的2×2权重固定阵列。激活纵向传播，INT32 部分和横向传播，右边界按行流出两列结果。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clk` | 输入 1 bit | 工作时钟。 |
| `rst` | 输入 1 bit | 同步高有效复位，包括清除 PE 权重。 |
| `clear` | 输入 1 bit | 清空流水数据和 valid，不清驻留权重。 |
| `step` | 输入 1 bit | 为1时所有 PE 在上升沿推进一次。 |
| `weight_load` | 输入 1 bit | 在上升沿把 `weight_matrix` 四个字节分别装入四个 PE。 |
| `weight_matrix` | 输入 32 bit | 打包的2×2 INT8权重。 |
| `activation_top_col0/1` | 输入 signed 8 bit | 两路错拍激活输入。 |
| `activation_valid_col0/1` | 输入 1 bit | 对应激活输入有效。 |
| `result_col0_stream` | 输出 signed 32 bit | 输出矩阵第0列的逐行结果流。 |
| `result_col0_valid` | 输出 1 bit | 第0列结果流有效。 |
| `result_col1_stream` | 输出 signed 32 bit | 输出矩阵第1列的逐行结果流。 |
| `result_col1_valid` | 输出 1 bit | 第1列结果流有效。 |

### `MacPE`

单个权重固定处理单元。保存一个 INT8 权重，计算 `partial_sum_in + activation_in × weight`，并寄存传播激活、部分和及 valid。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clk` | 输入 1 bit | 工作时钟。 |
| `rst` | 输入 1 bit | 同步高有效复位，权重和流水寄存器清零。 |
| `clear` | 输入 1 bit | 清流水寄存器和 valid，不清权重。优先于 `enable`。 |
| `enable` | 输入 1 bit | 上升沿流水推进使能。 |
| `weight_load` | 输入 1 bit | 上升沿将 `weight_in` 装入驻留权重，独立于 `enable`。 |
| `weight_in` | 输入 signed 8 bit | 新的驻留 INT8 权重。 |
| `activation_in` | 输入 signed 8 bit | 当前激活数据。 |
| `activation_valid_in` | 输入 1 bit | 当前激活有效。 |
| `activation_out` | 输出 signed 8 bit | 寄存后向下一个 PE 传播的激活。 |
| `activation_valid_out` | 输出 1 bit | 传播激活有效。 |
| `partial_sum_in` | 输入 signed 32 bit | 左侧传来的 INT32 部分和。 |
| `partial_sum_valid_in` | 输入 1 bit | 输入部分和有效。 |
| `partial_sum_out` | 输出 signed 32 bit | 两个输入 valid 同时为1时更新的乘加结果。 |
| `partial_sum_valid_out` | 输出 1 bit | 本拍输出乘加结果有效。 |

### `ResultCollector`

把阵列右边界的两路逐行结果流重新组合成四个 INT32 矩阵元素。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clk` | 输入 1 bit | 工作时钟。 |
| `rst` | 输入 1 bit | 同步高有效复位。 |
| `clear` | 输入 1 bit | 清空四个结果和两路行索引。 |
| `result_col0_stream` | 输入 signed 32 bit | 输出列0的结果流，第一次有效写 `sum00`，第二次写 `sum10`。 |
| `result_col0_valid` | 输入 1 bit | 列0结果有效。 |
| `result_col1_stream` | 输入 signed 32 bit | 输出列1的结果流，第一次有效写 `sum01`，第二次写 `sum11`。 |
| `result_col1_valid` | 输入 1 bit | 列1结果有效。 |
| `sum00/sum01/sum10/sum11` | 输出 signed 32 bit | 收集完成的2×2 INT32累加结果，保持到清除或下一次有效流覆盖。 |

### `Bias`

纯组合 INT32 Bias 加法器。

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| `sum_in` | 输入 signed 32 bit | MAC 累加结果。 |
| `bias_in` | 输入 signed 32 bit | 与累加结果处于相同量化尺度的 Bias。 |
| `biased_sum_out` | 输出 signed 32 bit | `sum_in + bias_in` 的低32位二补码结果。 |
| `overflow` | 输出 1 bit | 同号操作数相加得到异号结果时为1；只报告，不做饱和。 |

### `Requantize`

纯组合 INT32 到 INT8 重量化单元，执行算术右移和有符号饱和，不做舍入，零点固定为0。

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| `data_in` | 输入 signed 32 bit | Bias 后的累加值。 |
| `shift` | 输入 5 bit | 算术右移量0～31。 |
| `data_out` | 输出 signed 8 bit | 右移后限制到 `[-128,127]` 的 INT8 结果。 |

### `ReLU`

纯组合 INT8 激活函数。

| 端口 | 方向/位宽 | 含义 |
|---|---|---|
| `data_in` | 输入 signed 8 bit | 重量化后的 INT8 数据。 |
| `data_out` | 输出 signed 8 bit | 输入为负时输出0，否则原样输出。 |

### `VPU`

四路并行执行 `Bias -> Requantize -> ReLU`，并在写使能上升沿锁存打包结果。Bias0广播到输出列0，Bias1广播到输出列1。

| 端口 | 方向/位宽 | 含义与时序 |
|---|---|---|
| `clk` | 输入 1 bit | 结果寄存器时钟。 |
| `rst` | 输入 1 bit | 同步高有效复位，将结果矩阵清零。 |
| `result_write_enable` | 输入 1 bit | 上升沿结果锁存使能。 |
| `bias_vector` | 输入 64 bit | `[31:0]=bias0`、`[63:32]=bias1`。 |
| `quant_shift` | 输入 5 bit | 四路共用的算术右移量。 |
| `sum00/sum01/sum10/sum11` | 输入 signed 32 bit | ResultCollector 提供的四个累加值。 |
| `result_matrix` | 输出 32 bit | 四个 ReLU 后 INT8 结果，按通用矩阵约定打包并保持。 |
| `bias_overflow` | 输出 1 bit | 四路 Bias 加法溢出的组合 OR；仅在结果写回时由顶层记录为错误。 |

## 跨模块时序规则

- `io_btn`、`io_dip` 和 `io_customIn` 只能在 `TileInputSynchronizer` 之后被功能逻辑使用。
- `io_ramRdata` 是 Shared RAM 的异步读数据，必须与当前地址作为同一 RAM 事务理解，不能单独加两级同步器。
- 手动和主机模块产生的启动、清除与写请求都是单周期脉冲；顶层在模式交接前等待已接受脉冲被消费。
- `XorNetworkController.busy=1` 时独占 RAM；空闲时 RAM 交给当前手动或外部模式。
- Core 的结果使用ready-valid握手，Tile 网络的 `done` 是供人机和软件观察的粘滞状态。
- 多位异步输入经过两级同步仍不天然具备原子性；DIP 使用稳定窗口，主机总线使用 Request/ACK Toggle 协议。
