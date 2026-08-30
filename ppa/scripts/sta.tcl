# 使用iSTA/iPA分析Yosys映射后的门级网表。
# argv: SDC NETLIST DESIGN LIBERTY

set SDC_FILE  [lindex $argv 0]
set NETLIST   [lindex $argv 1]
set DESIGN    [lindex $argv 2]
set LIBERTY   [lindex $argv 3]
set RESULT_DIR [file dirname $NETLIST]

set_design_workspace $RESULT_DIR
read_netlist $NETLIST
read_liberty $LIBERTY
link_design $DESIGN
read_sdc $SDC_FILE

report_timing -max_path 5

# 当前没有门级仿真活动文件，先用统一的0.1默认翻转率做相对功耗比较。
report_power -toggle 0.1
