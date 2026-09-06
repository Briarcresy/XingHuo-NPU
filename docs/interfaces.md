# 接口与存储器

## MPSoC-Digital Tile 接口

用户模块为 `XingHuoNpuTile`。端口严格采用官方固定名称和位宽：`clock`、`reset`、8-bit LED/BTN/DIP、两位 4-bit 七段显示值、16-bit customIn/customOut，以及 256×8 Shared RAM 的地址、写使能、写数据和异步读数据。最终 `Tile` 包装器由官方 `make export` 生成。

`reset`为高有效同步复位。`io_ledUpdate`和`io_hex7segUpdate`持续为 1。

## Shared RAM Map（共享存储器地址表）

多字节数值使用 Little Endian（小端）顺序。

| 地址 | 长度 | 含义 |
| :-- | :-- | :-- |
| `0x00..0x03` | 4 B | 输入激活矩阵，4×INT8 |
| `0x10..0x13` | 4 B | 第一层权重，4×INT8 |
| `0x14..0x1B` | 8 B | 第一层 Bias，2×INT32 |
| `0x1C` | 1 B | 第一层 Shift，使用低 5 bit |
| `0x20..0x23` | 4 B | 隐藏层结果，4×INT8 |
| `0x30..0x33` | 4 B | 第二层权重，4×INT8 |
| `0x34..0x3B` | 8 B | 第二层 Bias，2×INT32 |
| `0x3C` | 1 B | 第二层 Shift，使用低 5 bit |
| `0x40..0x43` | 4 B | 最终结果，4×INT8 |
| `0x44` | 1 B | 分类结果，bit 0 有效 |
| `0x45` | 1 B | 状态：bit0 valid、bit2 error、bit3 demo |
| `0x46` | 1 B | Core 错误码，低 5 bit 有效 |

RAM 为异步读；写入在 `clock` 上升沿且 `io_ramWen=1` 时发生。

## External Host Protocol（外部主机协议）

`io_customIn[15]`请求外部模式；`[11:9]`是 Opcode；`[8]`是 Request Toggle；`[7:0]`是 Payload。写操作的 ACK 在 RAM 已采样写请求后返回。

主机协议的时间要求（T 为 Tile 时钟周期）：

1. 复位期间请求 Toggle 置 0，放弃复位前未完成的事务；复位至少覆盖三个有效时钟沿。
2. 请求外部模式后，等待 `io_customOut[14]=1`。
3. 设置 Payload/Opcode 并保持至少 3T，再翻转 Request Toggle。在 100 MHz 下为至少 30 ns。
4. 保持 Payload/Opcode/模式/Toggle，直到观察到 ACK 与请求一致。一次只能有一个未完成请求。
5. 主机也应同步采样 ACK；读取结果数据时，在观察 ACK 后再留至少一个主机采样周期。
6. busy 期间可以保持一个待处理请求，空闲后才会执行并应答；超时必须包含剩余网络执行时间。不得在未应答时覆盖请求。

START 的 ACK 表示启动命令已接受，网络状态最迟下一拍更新。轮询时先观察 busy 或 done 清零，再等待 done 置位，避免误读上次任务的 sticky done。

模式请求变化后停止接收旧模式新命令；已接受的写入、启动、清状态脉冲先完成，再交接模式。运算期间模式保持不变。

BTN、DIP 和 customIn 均经过两级同步寄存器，带 `ASYNC_REG` 标记。多位总线一致性仍依赖上述稳定窗口和最终布线偏差预算；两级同步不等同于 CDC 签核。DIP 应在按键前至少稳定 3T，并保持到去抖后的操作完成。机械拨码变化后应待其稳定再按按钮。

reset 是平台提供的同步信号，必须由上层满足时序。Tile 在 reset 有效时立即屏蔽 RAM 写使能，Shared RAM 不要求复位；复位后须重新写入完整可编程参数，或运行不依赖 RAM 初值的固定 Demo。

典型任务：设置地址，逐字节写入参数，启动，等待 done，再从 `0x40`读取输出、分类和状态。

## Display（显示）

| 页面 | 内容 |
| :-- | :-- |
| 0 | 状态与分类 |
| 1 | 当前 RAM 地址/数据 |
| 2..5 | 隐藏层结果的 4 个字节 |
| 6..9 | 最终结果的 4 个字节 |
| 10 | 分类结果 |
