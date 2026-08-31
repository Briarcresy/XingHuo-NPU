# XingHuo-NPU本地PPA评估

本目录只评估`filelists/rtl.f`列出的正式RTL，顶层固定为`XingHuo_NPU`；
`reference/`、`sim/`、`tests/`和`build/`不参与综合。生成物写入`build/ppa/`，
不会进入Git。

## 外部依赖

- Yosys（建议0.48或更新版本）；
- iEDA可执行文件，其中包含iSTA和iPA；
- ICsprout55开源PDK。

默认假设PDK位于：

```text
~/pdk/icsprout55
```

若路径不同，通过 `ICS55_PDK` 指定；iEDA通过 `IEDA_BIN` 指定。

## 使用方法

```bash
cd ~/XingHuo-NPU

make -C ppa check \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA

make -C ppa ppa \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA
```

默认配置为ICS55 RVT、TT、1.2V、25°C和300MHz。根目录
`constraints/XingHuo_NPU.sdc`记录相同的约3.333ns基础时钟假设；PPA流程会根据
`CLK_FREQ_MHZ`在对应build目录动态生成SDC。修改频率：

```bash
make -C ppa ppa CLK_FREQ_MHZ=50 \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA
```

选择LVT：

```bash
make -C ppa ppa VT=L \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA
```

每组配置使用独立输出目录，例如：

```text
build/ppa/XingHuo_NPU-300MHz-RVT/
```

关键报告：

- `synth_stat.txt`：标准单元数量及面积；
- `synth_check.txt`：未映射单元、多驱动等综合检查；
- `XingHuo_NPU.rpt`：建立/保持时间、WNS、TNS和关键路径；
- `XingHuo_NPU.pwr`：默认翻转率条件下的粗略功耗；
- `XingHuo_NPU_instance.pwr`：实例级功耗。

功耗暂时使用统一的0.1默认翻转率，只适合比较RTL版本。获得真实工作负载的门级
VCD/SAIF并完成寄生提取之前，不应把该数值当作芯片实际功耗。
