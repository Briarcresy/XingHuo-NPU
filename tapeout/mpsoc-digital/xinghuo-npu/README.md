# 星火 NPU：MPSoC-Digital Tile 版本

本目录是符合 MPSoC-Digital Tile v1 固定接口契约的独立用户设计包。正式导出
顶层由官方工具生成并命名为 `Tile`；用户模块为 `XinghuoNpuTile`。

## 目录边界

- `rtl/core/`：主项目 `src/` 的只读快照，使用脚本同步，不在这里单独修改。
- `rtl/XinghuoNpuTile.sv`：Tile v1 外围、共享 RAM 控制和 NPU Core 适配。
- `tests/XinghuoNpuTileTb.sv`：用户模块功能测试。
- `tests/XinghuoNpuTileHarnessTb.sv`：官方共享 RAM 环境集成测试。
- `design.json`：官方格式版本 1 的源码与测试清单，不包含硬件 ID 和 `ports`。

更新主项目 Core 后执行：

```sh
./tapeout/mpsoc-digital/scripts/sync_core.sh
```

## Tile v1 主机约定

固定接口本身不定义外部数据传输协议。本设计在不增加端口的前提下规定：

| 信号 | 用途 |
| --- | --- |
| `io_customIn[7:0]` | 命令载荷：地址、数据或控制位 |
| `io_customIn[8]` | 命令请求 toggle |
| `io_customIn[10:9]` | 操作码 |
| `io_customOut[7:0]` | 空闲时的共享 RAM 读数据 |
| `io_customOut[8]` | 命令应答 toggle |
| `io_customOut[9]` | Tile busy |
| `io_customOut[10]` | done，保持到主机清除 |
| `io_customOut[11]` | NPU Core busy |
| `io_customOut[15:12]` | 接口版本，当前为 `0001` |

`io_btn`和`io_dip`保留为官方规定的按键、拨码输入，不参与RAM传输。RAM地址由
Tile内部指针保存，避免要求用户用瞬时按键输入8位地址。

操作码定义：

| `io_customIn[10:9]` | 命令 | 载荷含义 |
| --- | --- | --- |
| `00` | 设置地址指针 | 新的8位RAM地址 |
| `01` | 写一个字节 | 写入当前地址，随后地址自动加1 |
| `10` | 读地址加1 | 当前读数据已在输出端，随后地址加1 |
| `11` | 控制 | bit0启动NPU，bit1清除done |

主机必须先稳定载荷和操作码，再翻转请求，并保持整条命令到应答toggle变为相同
值。这种握手可以避免异步输入脉冲过窄或被重复识别。

## 共享 RAM 布局

| 地址 | 内容 | 格式 |
| --- | --- | --- |
| `0x00–0x03` | 激活矩阵 | 4个 INT8，顺序00、01、10、11 |
| `0x04–0x07` | 权重矩阵 | 4个 INT8，顺序00、01、10、11 |
| `0x08–0x0B` | `bias_0` | INT32，小端序 |
| `0x0C–0x0F` | `bias_1` | INT32，小端序 |
| `0x10` | 重量化右移量 | 低5位有效 |
| `0x20–0x23` | 计算结果 | 4个 INT8，顺序00、01、10、11 |

## 严格按官方流程验证

先取得官方 `mpsoc-digital` user kit，然后在其仓库根目录执行：

```sh
make doctor

make check \
  DESIGN=/home/briarcresy/XingHuo-NPU/tapeout/mpsoc-digital/xinghuo-npu

make export \
  DESIGN=/home/briarcresy/XingHuo-NPU/tapeout/mpsoc-digital/xinghuo-npu

make export-check \
  DESIGN=/home/briarcresy/XingHuo-NPU/tapeout/mpsoc-digital/xinghuo-npu
```

`make check` 依次执行固定接口检查、lint、用户单测和单 Tile 共享资源测试。
`make export` 会重新检查并生成自包含的固定顶层 `Tile` 提交包。正式硬件 ID
由后续聚合平台分配，不应写进本目录。
