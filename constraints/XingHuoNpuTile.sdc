# 100 MHz前端估算约束；最终流片约束由MPSoC-Digital后端流程决定。
create_clock -name tile_clock -period 10.000 [get_ports clock]
