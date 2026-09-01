ROOT := $(abspath ..)
SHELL := /bin/bash

DESIGN ?= XingHuo_NPU
CLK_PORT ?= clk
CLK_FREQ_MHZ ?= 100
VT ?= R

# PDK与iEDA属于外部依赖，不提交进XingHuo-NPU仓库。
ICS55_PDK ?= $(HOME)/pdk/icsprout55
IEDA_BIN ?= $(HOME)/XingHuo-NPU/yosys-sta/bin/iEDA

RTL_FILELIST := $(ROOT)/filelists/rtl.f
RTL_REL_FILES := $(shell awk 'NF && substr($$1, 1, 1) != sprintf("%c", 35) { print $$1 }' "$(RTL_FILELIST)")
RTL_FILES := $(addprefix $(ROOT)/,$(RTL_REL_FILES))
BUILD_DIR ?= $(ROOT)/build/ppa/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-$(VT)VT
SCRIPT_DIR := $(ROOT)/ppa/scripts
SDC_FILE := $(BUILD_DIR)/$(DESIGN).sdc
NETLIST := $(BUILD_DIR)/$(DESIGN).netlist.v
TIMING_REPORT := $(BUILD_DIR)/$(DESIGN).rpt

STDCELL_ROOT := $(ICS55_PDK)/IP/STD_cell/ics55_LLSC_H7C_V1p10C100
LIBERTY := $(STDCELL_ROOT)/ics55_LLSC_H7C$(VT)/liberty/ics55_LLSC_H7C$(VT)_typ_tt_1p2_25_nldm.lib

.DEFAULT_GOAL := ppa

check:
	@test -f "$(RTL_FILELIST)" || { echo "ERROR: 缺少$(RTL_FILELIST)"; exit 1; }
	@test -n "$(RTL_FILES)" || { echo "ERROR: src/下没有找到Verilog RTL"; exit 1; }
	@test -f "$(ROOT)/src/XingHuo_NPU.v" || { echo "ERROR: 缺少顶层src/XingHuo_NPU.v"; exit 1; }
	@test -f "$(LIBERTY)" || { echo "ERROR: 找不到ICS55 Liberty: $(LIBERTY)"; echo "请设置 ICS55_PDK=/path/to/icsprout55-pdk"; exit 1; }
	@command -v yosys >/dev/null || { echo "ERROR: PATH中找不到yosys"; exit 1; }
	@test -x "$(IEDA_BIN)" || command -v "$(IEDA_BIN)" >/dev/null || { echo "ERROR: 找不到iEDA，请设置 IEDA_BIN=/path/to/iEDA"; exit 1; }
	@echo "RTL top : $(DESIGN)"
	@echo "RTL files: $(words $(RTL_FILES))"
	@echo "Clock    : $(CLK_FREQ_MHZ) MHz ($(CLK_PORT))"
	@echo "Liberty  : $(LIBERTY)"

$(BUILD_DIR):
	mkdir -p "$@"

$(SDC_FILE): | $(BUILD_DIR)
	@printf 'create_clock -name core_clock -period %.6f [get_ports %s]\n' "$$(awk 'BEGIN { print 1000.0 / $(CLK_FREQ_MHZ) }')" "$(CLK_PORT)" > "$@"

syn: check $(NETLIST)

$(NETLIST): $(RTL_FILELIST) $(RTL_FILES) $(SCRIPT_DIR)/synth.tcl Makefile | $(BUILD_DIR)
	@echo "正在进行Yosys综合与面积分析……"
	@set -o pipefail; \
		if ! echo tcl "$(SCRIPT_DIR)/synth.tcl" "$(DESIGN)" \"$(RTL_FILES)\" "$(LIBERTY)" "$@" "$(CLK_FREQ_MHZ)" "$(VT)" | \
			yosys -g -l "$(BUILD_DIR)/yosys.log" -s - > /dev/null 2>&1; then \
			echo "ERROR: Yosys综合失败，以下是日志末尾："; \
			tail -n 80 "$(BUILD_DIR)/yosys.log"; \
			exit 1; \
		fi
	@echo "Yosys综合完成，完整日志：$(BUILD_DIR)/yosys.log"

sta: check $(TIMING_REPORT)

$(TIMING_REPORT): $(NETLIST) $(SDC_FILE) $(SCRIPT_DIR)/sta.tcl Makefile
	@cd "$(BUILD_DIR)" && \
		if ! "$(IEDA_BIN)" -script "$(SCRIPT_DIR)/sta.tcl" "$(SDC_FILE)" "$(NETLIST)" "$(DESIGN)" "$(LIBERTY)" > "$(BUILD_DIR)/sta.log" 2>&1; then \
			tail -n 80 "$(BUILD_DIR)/sta.log"; \
			exit 1; \
		fi
	@echo "STA完成，完整日志：$(BUILD_DIR)/sta.log"

ppa: check sta
	@bash "$(SCRIPT_DIR)/summary.sh" "$(BUILD_DIR)" "$(DESIGN)"
	@echo
	@echo "PPA报告目录：$(BUILD_DIR)"
	@echo "面积：$(BUILD_DIR)/synth_stat.txt"
	@echo "时序：$(BUILD_DIR)/$(DESIGN).rpt"
	@echo "功耗：$(BUILD_DIR)/$(DESIGN).pwr"

clean:
	rm -rf "$(ROOT)/build/ppa"

.PHONY: check syn sta ppa clean
