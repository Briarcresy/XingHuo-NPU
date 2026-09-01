# xinghuo-npu

[English](README.en.md)

这是你的设计目录。你通常只需要修改 RTL 和两个测试文件，不需要修改
`FrameTop.sv` 或根目录下的 RTL。

## 先认识这些文件

| 文件 | 用途 | 是否需要修改 |
| --- | --- | --- |
| `rtl/XinghuoNpu.sv` | 你的电路代码 | 是，替换示例逻辑 |
| `tests/XinghuoNpuTb.sv` | 只测试你的电路 | 是，检查你的实际功能 |
| `tests/FrameXinghuoNpuTb.sv` | 测试电路接入整个工程后是否正常 | 是，检查外部引脚和 design 选择 |
| `design.json` | 告诉构建工具源码和测试在哪里 | 通常不需要 |

设计名称是 `xinghuo-npu`，顶层模块名是 `XinghuoNpu`。用户设计不需要填写
design ID；Frame 测试会自动使用临时 ID，正式 ID 由维护者合并时分配。

## 第一步：实现电路

打开 `rtl/XinghuoNpu.sv`，替换其中的示例逻辑。模块最外层的五个端口是工程与
你的电路之间的固定连接，初次使用时不要改名或删除：

- `clock`：时钟；纯组合电路可以不用，但必须保留端口。
- `reset`：复位；不需要复位的电路可以不用，但必须保留端口。
- `io_in[65:0]`：从外部引脚读到的 66 位输入。
- `io_out[65:0]`：准备送到外部引脚的 66 位输出值。
- `io_oe[65:0]`：输出开关；某一位为 1 时才会驱动对应外部引脚。

`io_*[n]` 对应芯片顶层的 `user_io[n + 7]`。例如，`io_in[0]` 对应
`user_io[7]`。

## 第二步：修改测试

两个 TB 文件开头都标明了哪些部分通常保留、哪些部分应按设计修改。

先修改 `tests/XinghuoNpuTb.sv`，测试你的电路功能。然后运行：

```sh
make user-lint
make user-test
```

看到测试文件中 `$display` 输出的 `PASS`，并且 make 正常结束，才表示测试通过。

## 第三步：测试 FrameTop 连接

不需要修改 `designs/registry.json`。构建工具会为未注册设计自动选择临时 ID：

```sh
make user-frame-test
```

Frame 测试会自动检查外部 `test_io_oe` 与设计 `io_oe` 是否重叠。请保留
Frame TB 中的 `reset`、`test_io_oe` 和 `dut` 名称；任意 payload 位由双方同时
使能时，仿真都会直接报错，即使驱动值相同。

最后运行提交前检查：

```sh
make user-check
```

当前框架要求使用 Verilator 5.050。构建脚本会自动探测非关键警告参数。

完整中文步骤见 `../../docs/cn/user-guide.md`。
