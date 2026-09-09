ROOT := $(abspath ..)
SHELL := /bin/bash

DESIGN ?= XingHuoNpuTile
CLK_PORT ?= clock
CLK_FREQ_MHZ ?= 200
VT ?= R
PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
TIMING_CONFIG ?= $(ROOT)/constraints/timing-estimate.json

# PDK与iEDA属于外部依赖，不提交进XingHuo-NPU仓库。
ICS55_PDK ?= $(HOME)/pdk/icsprout55-pdk
IEDA_BIN ?= $(HOME)/XingHuo-NPU/yosys-sta/bin/iEDA

RTL_FILELIST := $(ROOT)/filelists/tile.f
RTL_REL_FILES := $(shell awk 'NF && substr($$1, 1, 1) != sprintf("%c", 35) { print $$1 }' "$(RTL_FILELIST)")
RTL_FILES := $(addprefix $(ROOT)/,$(RTL_REL_FILES))
BUILD_DIR ?= $(ROOT)/build/ppa/$(DESIGN)-main-$(CLK_FREQ_MHZ)MHz-$(VT)VT
SCRIPT_DIR := $(ROOT)/ppa/scripts
SDC_FILE := $(BUILD_DIR)/$(DESIGN).sdc
NETLIST := $(BUILD_DIR)/$(DESIGN).netlist.v
TIMING_REPORT := $(BUILD_DIR)/$(DESIGN).rpt
CONFIG_STAMP := $(BUILD_DIR)/build-config.json

STDCELL_ROOT := $(ICS55_PDK)/IP/STD_cell/ics55_LLSC_H7C_V1p10C100
LIBERTY ?= $(STDCELL_ROOT)/ics55_LLSC_H7C$(VT)/liberty/ics55_LLSC_H7C$(VT)_typ_tt_1p2_25_nldm.lib
CELL_VERILOG ?= $(STDCELL_ROOT)/ics55_LLSC_H7C$(VT)/verilog/ics55_LLSC_H7C$(VT).v

.DEFAULT_GOAL := ppa
.DELETE_ON_ERROR:

check:
	@test -f "$(RTL_FILELIST)" || { echo "ERROR: 缺少$(RTL_FILELIST)"; exit 1; }
	@test -n "$(RTL_FILES)" || { echo "ERROR: Tile RTL文件列表为空"; exit 1; }
	@test -f "$(ROOT)/rtl/tile/XingHuoNpuTile.sv" || { echo "ERROR: 缺少Tile顶层rtl/tile/XingHuoNpuTile.sv"; exit 1; }
	@test -f "$(LIBERTY)" || { echo "ERROR: 找不到ICS55 Liberty: $(LIBERTY)"; echo "请设置 ICS55_PDK=/path/to/icsprout55-pdk"; exit 1; }
	@command -v yosys >/dev/null || { echo "ERROR: PATH中找不到yosys"; exit 1; }
	@test -x "$(IEDA_BIN)" || command -v "$(IEDA_BIN)" >/dev/null || { echo "ERROR: 找不到iEDA，请设置 IEDA_BIN=/path/to/iEDA"; exit 1; }
	@echo "RTL top : $(DESIGN)"
	@echo "RTL files: $(words $(RTL_FILES))"
	@echo "Clock    : $(CLK_FREQ_MHZ) MHz ($(CLK_PORT))"
	@echo "Liberty  : $(LIBERTY)"

$(BUILD_DIR):
	mkdir -p "$@"

# 路径/库内容/工具变化也必须触发重建，不能仅依赖lib文件的旧时间戳。
$(CONFIG_STAMP): FORCE | $(BUILD_DIR)
	@$(PYTHON) "$(SCRIPT_DIR)/build_config.py" --output "$@" \
		--design "$(DESIGN)" --frequency "$(CLK_FREQ_MHZ)" --vt "$(VT)" \
		--liberty "$(LIBERTY)" --cells "$(CELL_VERILOG)"

$(SDC_FILE): $(NETLIST) $(TIMING_CONFIG) $(SCRIPT_DIR)/generate_sdc.py Makefile | $(BUILD_DIR)
	@$(PYTHON) "$(SCRIPT_DIR)/generate_sdc.py" --config "$(TIMING_CONFIG)" \
		--netlist "$(NETLIST)" --period "$$(awk 'BEGIN { print 1000.0 / $(CLK_FREQ_MHZ) }')" --output "$@"

syn: check $(NETLIST)

$(NETLIST): $(CONFIG_STAMP) $(RTL_FILELIST) $(RTL_FILES) $(SCRIPT_DIR)/synth.tcl $(LIBERTY) Makefile | $(BUILD_DIR)
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
		if ! GLOG_log_dir="$(BUILD_DIR)" "$(IEDA_BIN)" -script "$(SCRIPT_DIR)/sta.tcl" "$(SDC_FILE)" "$(NETLIST)" "$(DESIGN)" "$(LIBERTY)" > "$(BUILD_DIR)/sta.log" 2>&1; then \
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

multi-corner: syn $(SDC_FILE)
	@$(PYTHON) "$(SCRIPT_DIR)/multi_corner.py" --netlist "$(NETLIST)" \
		--sdc "$(SDC_FILE)" --design "$(DESIGN)" --vt "$(VT)" \
		--lib-dir "$(STDCELL_ROOT)/ics55_LLSC_H7C$(VT)/liberty" \
		--ieda "$(IEDA_BIN)" --output "$(BUILD_DIR)/corners"

# 与综合同一映射网表，使用PDK真实功能模型；不含SDF时序回标。
gls: syn
	@$(MAKE) -C "$(ROOT)" xor-expected
	@test -f "$(CELL_VERILOG)"
	@$(IVERILOG) -g2012 -Dfunctional -s XingHuoNpuTileFourStateTb \
		-o "$(BUILD_DIR)/gate-sim" "$(BUILD_DIR)/$(DESIGN).sim.v" \
		"$(CELL_VERILOG)" "$(ROOT)/tests/rtl/XingHuoNpuTileFourStateTb.sv" \
		>"$(BUILD_DIR)/gate-build.log" 2>&1 || { tail -n 50 "$(BUILD_DIR)/gate-build.log"; exit 1; }
	@$(VVP) "$(BUILD_DIR)/gate-sim" +vectors="$(ROOT)/build/sim/network_vectors.txt" \
		>"$(BUILD_DIR)/gate-test.log" 2>&1 || { cat "$(BUILD_DIR)/gate-test.log"; exit 1; }
	@cat "$(BUILD_DIR)/gate-test.log"

clean:
	rm -rf "$(ROOT)/build/ppa"

.PHONY: check syn sta ppa gls multi-corner clean FORCE
FORCE:
