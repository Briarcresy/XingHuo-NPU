# 基础综合约束：当前PPA默认目标为100 MHz，即10 ns周期。
# 尚未确定封装和板级环境，因此这里不虚构输入延迟、输出延迟、驱动单元和负载。
create_clock -name core_clock -period 3.333333 [get_ports clk]
