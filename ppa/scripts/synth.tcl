# XingHuo-TPU使用ICS55标准单元的Yosys综合脚本。
# argv: DESIGN "RTL_FILES" LIBERTY NETLIST CLK_FREQ_MHZ VT

set DESIGN       [lindex $argv 0]
set RTL_FILES    [string map {"\"" ""} [lindex $argv 1]]
set LIBERTY      [lindex $argv 2]
set NETLIST      [lindex $argv 3]
set CLK_FREQ_MHZ [lindex $argv 4]
set VT           [lindex $argv 5]
set RESULT_DIR   [file dirname $NETLIST]
set PERIOD_PS    [expr 1000000.0 / $CLK_FREQ_MHZ]

yosys -import

foreach rtl $RTL_FILES {
    read_verilog $rtl
}

hierarchy -check -top $DESIGN
synth -top $DESIGN -flatten
opt_clean -purge

# 将时序单元和组合逻辑映射到ICS55。
dfflibmap -liberty $LIBERTY -dont_use LAT*

set ABC_CONSTR "$RESULT_DIR/abc.constr"
set fp [open $ABC_CONSTR w]
puts $fp "set_driving_cell BUFX0P5H7${VT}"
puts $fp "set_load 1.6"
close $fp

abc -liberty $LIBERTY -dont_use LAT* -D $PERIOD_PS -constr $ABC_CONSTR

# 映射常量驱动，避免门级网表保留抽象常量单元。
hilomap -singleton \
    -hicell TIEHIH7${VT} Z \
    -locell TIELOH7${VT} Z
setundef -zero
opt_clean -purge

# iEDA的Verilog解析器不能稳定处理带signed属性的多位门级连线。
# 将总线拆成标量并规范化内部网名；只改变网表表示，不改变电路结构。
autoname
splitnets -format __v -ports
opt_clean -purge

read_liberty -lib $LIBERTY
tee -o "$RESULT_DIR/synth_check.txt" check -mapped
tee -o "$RESULT_DIR/synth_stat.txt" stat -liberty $LIBERTY
write_verilog -noattr -noexpr -nohex -nodec "$NETLIST"
