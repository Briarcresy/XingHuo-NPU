# 200 MHz前端估算约束；最终流片约束由MPSoC-Digital后端流程决定。
create_clock -name tile_clock -period 5.000 [get_ports clock]
