# XingHuo-TPU本地PPA评估

本目录只评估 `src/` 下的正式RTL，顶层固定为 `XingHuo_TPU`；`reference/` 和
`yosys-sta/` 不参与综合。生成物写入 `build/ppa/`，不会进入Git。

## 外部依赖

- Yosys（建议0.48或更新版本）；
- iEDA可执行文件，其中包含iSTA和iPA；
- ICsprout55开源PDK。

默认假设PDK位于：

```text
~/icsprout55-pdk
```

若路径不同，通过 `ICS55_PDK` 指定；iEDA通过 `IEDA_BIN` 指定。

## 使用方法

```bash
cd ~/XingHuo-TPU

make -C ppa check \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA

make -C ppa ppa \
  ICS55_PDK=/path/to/icsprout55-pdk \
  IEDA_BIN=/path/to/iEDA
```

默认配置为ICS55 RVT、TT、1.2V、25°C和100MHz。修改频率：

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
build/ppa/XingHuo_TPU-100MHz-RVT/
```

关键报告：

- `synth_stat.txt`：标准单元数量及面积；
- `synth_check.txt`：未映射单元、多驱动等综合检查；
- `XingHuo_TPU.rpt`：建立/保持时间、WNS、TNS和关键路径；
- `XingHuo_TPU.pwr`：默认翻转率条件下的粗略功耗；
- `XingHuo_TPU_instance.pwr`：实例级功耗。

功耗暂时使用统一的0.1默认翻转率，只适合比较RTL版本。获得真实工作负载的门级
VCD/SAIF并完成寄生提取之前，不应把该数值当作芯片实际功耗。
