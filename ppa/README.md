# PPA 估算

本目录使用 Yosys、ICS55 Liberty 和 iEDA 对完整 `XingHuoNpuTile`进行前端 PPA 估算。RTL 来自 `filelists/tile.f`，默认时钟端口为 `clock`、频率为 150 MHz。

```bash
make -C ppa check ICS55_PDK=~/pdk/icsprout55-pdk IEDA_BIN=/path/to/iEDA
make -C ppa ppa   ICS55_PDK=~/pdk/icsprout55-pdk IEDA_BIN=/path/to/iEDA
make gls
make multi-corner
```

结果位于 `build/ppa/XingHuoNpuTile-main-150MHz-RVT/`：`synth_stat.txt`是面积，`XingHuoNpuTile.rpt`是 STA（静态时序分析），`XingHuoNpuTile.pwr`是默认活动率功耗，日志保存在 `yosys.log`和`sta.log`。

可用 `CLK_FREQ_MHZ=<MHz>`改变时钟假设。综合面积包含 Core 和 Tile 外围，但不包含 SoC 共享资源。结果不是 Placement and Routing（布局布线）后的签核。

默认PDK为`~/pdk/icsprout55-pdk`。已核对main提交`68d89edb47847671e18f9e65d66c0cd883995e05`及v1.10.102附件：HVT/LVT/RVT各7个Liberty角。旧ysyx分支`6bc74eee`的MUXI2 Verilog模型有输出自反馈/多驱动缺陷，新版本已经修复。工程不修改PDK，也不通过屏蔽X来通过门级测试。

`build-config.json`记录所选Liberty、单元模型的路径和SHA256及Yosys版本；切换库会使综合重建。默认RVT设计的多角检查在同一份TT综合网表上依次加载7个RVT库，输出`corners/summary.md`和`summary.json`。HVT/LVT为不同单元族，不应把RVT网表直接链接到它们；若改为`VT=L`或`VT=H`，会重新映射相应单元族。

`constraints/timing-estimate.json`中的输入/输出延迟、负载、转换时间、时钟不确定度都是明确标记的探索性预算。周期由`CLK_FREQ_MHZ`决定。SDC生成器检查42个输入和51个输出的覆盖，时钟以外每个输入和所有输出都有约束；没有添加全局false path。仓库`constraints/XingHuoNpuTile.sdc`仅为早期时钟参考，不用于此流程。

多角分析没有布局提取的RC或时钟树，库名中的`rcbest/rcworst`不意味着已经读入芯片寄生参数。负hold slack必须保留给后端物理修复与复查，不应通过修改探索性预算掩盖。

`make gls`使用带总线端口的`.sim.v`网表和PDK功能模型，默认不启用specify延迟。STA所用标量网表来自同一次映射，仅做命名和总线拆分。两种表示均需要保留在可追溯报告中。测试台支持`+trace=<path>`输出门级VCD用于后续活动分析；当前iPA报告仍使用默认0.1活动率。
