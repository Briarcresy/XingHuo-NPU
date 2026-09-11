# 架构图源与编辑

这里的 `.drawio` 是唯一权威图源，`.svg` 是由它导出的文档预览。模块、文字、边界和连线均为原生对象，不是整图位图；连线通过端点附着到对象，移动模块时会跟随。

完整读图说明见 [架构文档](../architecture.md)。图源按层次拆开，每个文件只有一张图：

| 图源 | 用途 | 对应 RTL |
| :-- | :-- | :-- |
| [tile-overview.drawio](tile-overview.drawio) | Tile 内外边界、控制、计算与 RAM 通路 | [XingHuoNpuTile.sv](../../rtl/tile/XingHuoNpuTile.sv) 及 `rtl/tile/` 子模块 |
| [core-architecture.drawio](core-architecture.drawio) | Core 主数据通路与任务控制 | [XingHuo_NPU.v](../../rtl/core/XingHuo_NPU.v)、ControlUnit、MatrixFeeder、ResultCollector |
| [systolic-array.drawio](systolic-array.drawio) | 2×2 PE 排列、权重映射与传播方向 | [SystolicArray.v](../../rtl/core/SystolicArray.v)、[MatrixFeeder.v](../../rtl/core/MatrixFeeder.v) |
| [mac-pe.drawio](mac-pe.drawio) | 组合 MAC 与驻留权重、流水寄存器边界 | [MacPE.v](../../rtl/core/MacPE.v) |
| [vpu.drawio](vpu.drawio) | 一个后处理通道，实际四路并行 | [VPU.v](../../rtl/core/VPU.v)、[Bias.v](../../rtl/core/Bias.v)、[Requantize.v](../../rtl/core/Requantize.v)、[ReLU.v](../../rtl/core/ReLU.v) |
| [xor-sequence.drawio](xor-sequence.drawio) | 两层执行顺序与真实隐藏层反馈 | [XorNetworkController.sv](../../rtl/tile/XorNetworkController.sv) |

## 用图形界面修改

1. 使用 diagrams.net 网页版或 draw.io 桌面版，选择 **File → Open from → Device**，打开要修改的 `.drawio`；桌面版也可直接打开文件。
2. 拖动方框调整位置，双击文字修改标签；选中连线可调整折点。需要新连线时，从模块的连接点拖向另一个模块，不要仅把线端摆在模块附近。
3. 保存回原 `.drawio` 文件，再选择 **File → Export as → SVG**。
4. 导出白色背景、整张图（不是仅选中对象），边距可设为 20；启用 **Include a copy of my diagram**，替换同名 `.svg`。
5. 打开 Markdown 预览，检查文字大小、裁切和交叉线。提交时同时包含修改后的 `.drawio` 与 `.svg`。

SVG 内含可编辑图数据以便恢复，但日常仍应编辑 `.drawio`，不要分别维护两套内容。图内使用短英文标签，中文解释保留在架构文档，避免小字号和冗长文字。

## 命令行重新导出

安装 draw.io 桌面版且 `drawio` 在 PATH 后，在项目根目录执行：

```bash
# 只读取现有图源，更新同名 SVG；不会生成或覆盖 .drawio。
bash docs/diagrams/export.sh
```

也可以只导出某一张：

```bash
drawio --export --format svg --embed-diagram --embed-svg-fonts false \
    --theme light --border 20 docs/diagrams/tile-overview.drawio
```

命令行导出依赖 Electron 图形运行环境。若无桌面会话或遇到 Snap 权限限制，使用桌面界面导出；不要把其他格式重命名成 SVG。当前图已用 draw.io 31.3.2 导出，SVG 可由浏览器和 Markdown 预览。

## 修改边界

- 图展示功能架构，不代替 RTL 或接口契约。功能分组与真实模块的对应关系见架构文档。
- 修改连接关系前核实 RTL，特别是 PE 权重位置、Activation/Partial Sum 方向及 Ready/Valid 的反向信号。
- 不在总图堆入端口表、RAM 地址表或门级电路；这些信息应保留在独立文档中。
- 仓库不保留自动重建图源的生成器，避免覆盖手工布局；导出脚本只更新 SVG。
