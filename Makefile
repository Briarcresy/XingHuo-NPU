SHELL := /bin/bash

PYTHON ?= python3
VERILATOR ?= verilator
IVERILOG ?= iverilog
VVP ?= vvp
MPSOC_DIGITAL ?= $(if $(wildcard $(CURDIR)/build/mpsoc-digital/Makefile),$(CURDIR)/build/mpsoc-digital,$(HOME)/mpsoc-digital)
ICS55_PDK ?= $(HOME)/pdk/icsprout55-pdk
IEDA_BIN ?= $(CURDIR)/yosys-sta/bin/iEDA

CORE_TOP := XingHuo_NPU
TILE_TOP := XingHuoNpuTile
CORE_FILELIST := filelists/core.f
TILE_FILELIST := filelists/tile.f
CORE_RTL := $(shell awk 'NF && substr($$1,1,1) != sprintf("%c",35) {print $$1}' $(CORE_FILELIST))
TILE_RTL := $(shell awk 'NF && substr($$1,1,1) != sprintf("%c",35) {print $$1}' $(TILE_FILELIST))

BUILD_DIR := build
CORE_SIM_DIR := $(BUILD_DIR)/core-verilator
CORE_SIM := $(CORE_SIM_DIR)/V$(CORE_TOP)
VECTOR_FILE := $(BUILD_DIR)/sim/test_vectors.txt
TILE_TEST_DIR := $(BUILD_DIR)/tile-test
CORE_SVA_DIR := $(BUILD_DIR)/core-sva
TILE_SVA_DIR := $(BUILD_DIR)/tile-sva
LINT_LOG := $(BUILD_DIR)/lint/verilator.log
CORE_BUILD_LOG := $(BUILD_DIR)/sim/core-build.log
TILE_TEST_LOG := $(TILE_TEST_DIR)/verilator.log
CORE_SVA_LOG := $(CORE_SVA_DIR)/verilator.log
TILE_SVA_LOG := $(TILE_SVA_DIR)/verilator.log

TEST_COUNT ?= 1000
TEST_SEED ?= 0x20260831

VERILATOR_FLAGS := --timing --Wall -Werror-PINMISSING \
	-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-DECLFILENAME \
	-Wno-BLKSEQ -Wno-PINCONNECTEMPTY

.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

define print_info
	@if [ -t 1 ]; then printf '\033[1;36m%s\033[0m\n' "$(1)"; else printf '%s\n' "$(1)"; fi
endef
define print_success
	@if [ -t 1 ]; then printf '\033[1;32m%s\033[0m\n' "$(1)"; else printf '%s\n' "$(1)"; fi
endef

help:
	@printf '%s\n' '星火NPU MPSoC-Digital常用命令：'
	@printf '%s\n' '  make lint             检查Core和Tile正式RTL'
	@printf '%s\n' '  make test             运行Golden Model、Core、Tile和SVA验证'
	@printf '%s\n' '  make doctor           检查官方框架工具版本'
	@printf '%s\n' '  make official-check   使用官方框架运行lint/unit/harness检查'
	@printf '%s\n' '  make official-export  官方检查、导出并执行独立export-check'
	@printf '%s\n' '  make ppa              运行ICS55 Tile PPA估算'
	@printf '%s\n' '  make gls              使用ICS55单元模型运行四态门级功能验证'
	@printf '%s\n' '  make multi-corner     对同一网表运行7个库角STA估算'
	@printf '%s\n' '  make release-check    完整检查并归档源码/官方导出/报告/哈希'
	@printf '%s\n' '  make clean            删除本项目build生成物'

vectors: sim/golden_model.py sim/generate_vectors.py
	@mkdir -p "$(dir $(VECTOR_FILE))"
	@$(PYTHON) sim/generate_vectors.py --count "$(TEST_COUNT)" \
		--seed "$(TEST_SEED)" --output "$(VECTOR_FILE)"

xor-expected: sim/golden_model.py sim/generate_xor_expected.py
	@$(PYTHON) sim/generate_xor_expected.py

python-test:
	$(call print_info,Running Python Golden Model tests...)
	@$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v
	$(call print_success,PYTHON GOLDEN MODEL TESTS PASSED)

$(CORE_SIM): $(CORE_FILELIST) $(CORE_RTL) sim/XingHuo_NPU_sim.cpp
	@mkdir -p "$(CORE_SIM_DIR)" "$(dir $(CORE_BUILD_LOG))"
	$(call print_info,Building Verilator Core model...)
	@if ! $(VERILATOR) --cc --exe --build --language 1364-2005 \
		$(VERILATOR_FLAGS) --top-module "$(CORE_TOP)" --Mdir "$(CORE_SIM_DIR)" \
		-CFLAGS '-std=c++17' -f "$(CORE_FILELIST)" sim/XingHuo_NPU_sim.cpp \
		>"$(CORE_BUILD_LOG)" 2>&1; then \
		printf '\033[1;31m%s\033[0m\n' 'ERROR: Core构建失败，日志末尾：' >&2; \
		tail -n 80 "$(CORE_BUILD_LOG)"; exit 1; fi

core-test: vectors $(CORE_SIM)
	$(call print_info,Running randomized NPU Core tests...)
	@"$(CORE_SIM)" "$(VECTOR_FILE)"

tile-test: xor-expected $(TILE_FILELIST) $(TILE_RTL) tests/rtl/XorExpectedPkg.sv tests/rtl/XingHuoNpuTileTb.sv verification/XingHuoNpuTile_assertions.sv
	@mkdir -p "$(TILE_TEST_DIR)"
	$(call print_info,Running manual/external two-layer XOR Tile tests...)
	@if ! $(VERILATOR) --binary --assert $(VERILATOR_FLAGS) \
		--top-module XingHuoNpuTileTb --Mdir "$(TILE_TEST_DIR)/obj" \
		-f "$(TILE_FILELIST)" tests/rtl/XorExpectedPkg.sv \
		verification/XingHuoNpuTile_assertions.sv \
		tests/rtl/XingHuoNpuTileTb.sv \
		>"$(TILE_TEST_LOG)" 2>&1; then \
		printf '\033[1;31m%s\033[0m\n' 'ERROR: Tile构建失败，日志末尾：' >&2; \
		tail -n 80 "$(TILE_TEST_LOG)"; exit 1; fi
	@if ! "$(TILE_TEST_DIR)/obj/VXingHuoNpuTileTb" >>"$(TILE_TEST_LOG)" 2>&1; then \
		printf '\033[1;31m%s\033[0m\n' 'ERROR: Tile测试失败，日志末尾：' >&2; \
		tail -n 80 "$(TILE_TEST_LOG)"; exit 1; fi
	@grep -q 'XINGHUO NPU TILE UNIT TEST PASS' "$(TILE_TEST_LOG)"
	$(call print_success,MANUAL/EXTERNAL XOR TILE TESTS PASSED)

core-sva: $(CORE_FILELIST) $(CORE_RTL) verification/XingHuo_NPU_assertions.sv verification/XingHuo_NPU_sva_tb.sv
	@mkdir -p "$(CORE_SVA_DIR)"
	$(call print_info,Running NPU Core SVA...)
	@if ! $(VERILATOR) --binary --assert $(VERILATOR_FLAGS) \
		--top-module XingHuo_NPU_sva_tb --Mdir "$(CORE_SVA_DIR)/obj" \
		-f "$(CORE_FILELIST)" verification/XingHuo_NPU_assertions.sv \
		verification/XingHuo_NPU_sva_tb.sv >"$(CORE_SVA_LOG)" 2>&1 \
		|| ! "$(CORE_SVA_DIR)/obj/VXingHuo_NPU_sva_tb" >>"$(CORE_SVA_LOG)" 2>&1; then \
		tail -n 80 "$(CORE_SVA_LOG)"; exit 1; fi
	@grep -q 'NPU CORE SVA TEST PASS' "$(CORE_SVA_LOG)"
	$(call print_success,NPU CORE SVA PASSED)

tile-sva: $(TILE_FILELIST) $(TILE_RTL) verification/XingHuoNpuTile_assertions.sv verification/XingHuoNpuTile_sva_tb.sv
	@mkdir -p "$(TILE_SVA_DIR)"
	$(call print_info,Running MPSoC-Digital Tile SVA...)
	@if ! $(VERILATOR) --binary --assert $(VERILATOR_FLAGS) \
		--top-module XingHuoNpuTile_sva_tb --Mdir "$(TILE_SVA_DIR)/obj" \
		-f "$(TILE_FILELIST)" verification/XingHuoNpuTile_assertions.sv \
		verification/XingHuoNpuTile_sva_tb.sv >"$(TILE_SVA_LOG)" 2>&1 \
		|| ! "$(TILE_SVA_DIR)/obj/VXingHuoNpuTile_sva_tb" >>"$(TILE_SVA_LOG)" 2>&1; then \
		tail -n 80 "$(TILE_SVA_LOG)"; exit 1; fi
	@grep -q 'NPU TILE SVA TEST PASS' "$(TILE_SVA_LOG)"
	$(call print_success,MPSoC-DIGITAL TILE SVA PASSED)

sva-test: core-sva tile-sva

lint: $(TILE_FILELIST) $(TILE_RTL)
	@mkdir -p "$(dir $(LINT_LOG))"
	$(call print_info,Linting official Tile v1 RTL...)
	@if ! $(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module "$(TILE_TOP)" \
		-f "$(TILE_FILELIST)" >"$(LINT_LOG)" 2>&1; then \
		tail -n 80 "$(LINT_LOG)"; exit 1; fi
	$(call print_success,TILE RTL LINT PASSED)

four-state-test: xor-expected
	@mkdir -p "$(BUILD_DIR)/four-state"
	@$(IVERILOG) -g2012 -s XingHuoNpuTileFourStateTb \
		-o "$(BUILD_DIR)/four-state/sim" -f "$(TILE_FILELIST)" \
		tests/rtl/XingHuoNpuTileFourStateTb.sv >"$(BUILD_DIR)/four-state/build.log" 2>&1 \
		|| { tail -n 50 "$(BUILD_DIR)/four-state/build.log"; exit 1; }
	@$(VVP) "$(BUILD_DIR)/four-state/sim" >"$(BUILD_DIR)/four-state/test.log" 2>&1 \
		|| { cat "$(BUILD_DIR)/four-state/test.log"; exit 1; }
	@cat "$(BUILD_DIR)/four-state/test.log"

test: python-test core-test tile-test sva-test four-state-test
	$(call print_success,ALL LOCAL TESTS AND VERIFICATION PASSED)

doctor:
	@test -f "$(MPSOC_DIGITAL)/Makefile" || { \
		printf 'ERROR: 找不到官方框架：%s\n' "$(MPSOC_DIGITAL)"; exit 1; }
	@$(MAKE) -C "$(MPSOC_DIGITAL)" doctor

official-check:
	@test -f "$(MPSOC_DIGITAL)/Makefile" || { \
		printf 'ERROR: 找不到官方框架：%s\n' "$(MPSOC_DIGITAL)"; exit 1; }
	@mkdir -p "$(BUILD_DIR)/official"
	$(call print_info,Running official MPSoC-Digital check...)
	@if ! $(MAKE) -C "$(MPSOC_DIGITAL)" check DESIGN="$(CURDIR)" \
		>"$(BUILD_DIR)/official/check.log" 2>&1; then \
		printf '\033[1;31m%s\033[0m\n' 'ERROR: 官方check失败，日志末尾：' >&2; \
		tail -n 80 "$(BUILD_DIR)/official/check.log"; exit 1; fi
	$(call print_success,OFFICIAL MPSoC-DIGITAL CHECK PASSED)

official-export: official-check
	$(call print_info,Exporting and independently checking final Tile package...)
	@input_dir=$$($(PYTHON) scripts/prepare_official.py --parent "$(BUILD_DIR)/official") || exit 1; \
	if ! $(MAKE) -C "$(MPSOC_DIGITAL)" export DESIGN="$$input_dir" \
		>"$(BUILD_DIR)/official/export.log" 2>&1 \
		|| ! $(MAKE) -C "$(MPSOC_DIGITAL)" export-check DESIGN="$$input_dir" \
		>"$(BUILD_DIR)/official/export-check.log" 2>&1; then \
		printf '\033[1;31m%s\033[0m\n' 'ERROR: 官方export/export-check失败，日志末尾：' >&2; \
		tail -n 80 "$(BUILD_DIR)/official/export.log" 2>/dev/null; \
		tail -n 80 "$(BUILD_DIR)/official/export-check.log" 2>/dev/null; exit 1; fi
	$(call print_success,OFFICIAL TILE EXPORT AND EXPORT-CHECK PASSED)

ppa-check:
	@$(MAKE) -C ppa check

ppa:
	@$(MAKE) -C ppa ppa

gls:
	@$(MAKE) -C ppa gls

multi-corner:
	@$(MAKE) -C ppa multi-corner

release-check:
	@$(PYTHON) scripts/release_check.py --framework "$(MPSOC_DIGITAL)" \
		--pdk "$(ICS55_PDK)" --ieda "$(IEDA_BIN)"

clean:
	@rm -rf "$(BUILD_DIR)"

.PHONY: help vectors xor-expected python-test core-test tile-test core-sva tile-sva sva-test doctor \
	lint test official-check official-export ppa-check ppa clean
.PHONY: four-state-test gls multi-corner release-check
