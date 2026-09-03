SHELL := /bin/bash

PYTHON ?= python3
VERILATOR ?= verilator
TOP := XingHuo_NPU

RTL_FILELIST := filelists/rtl.f
RTL_FILES := $(shell awk 'NF && substr($$1, 1, 1) != sprintf("%c", 35) { print $$1 }' "$(RTL_FILELIST)")
SIM_CPP := $(abspath sim/XingHuo_NPU_sim.cpp)
GOLDEN_MODEL := sim/golden_model.py
VECTOR_GENERATOR := sim/generate_vectors.py
PYTHON_TESTS := $(wildcard tests/test_*.py)

BUILD_DIR := build
SIM_BUILD_DIR := $(BUILD_DIR)/sim
VERILATOR_DIR := $(BUILD_DIR)/verilator
SIM_BINARY := $(VERILATOR_DIR)/V$(TOP)
VECTOR_FILE := $(SIM_BUILD_DIR)/test_vectors.txt
LINT_LOG := $(BUILD_DIR)/lint/verilator.log
BUILD_LOG := $(SIM_BUILD_DIR)/verilator_build.log
SVA_BUILD_DIR := $(BUILD_DIR)/sva
SVA_LOG := $(SVA_BUILD_DIR)/verilator.log

TEST_COUNT ?= 1000
TEST_SEED ?= 0x20260831

# 颜色只用于交互式终端。输出被重定向到文件或CI日志时自动退化为纯文本，
# 避免把ANSI转义字符写入日志。
define print_info
	@if [ -t 1 ]; then printf '\033[1;36m%s\033[0m\n' "$(1)"; else printf '%s\n' "$(1)"; fi
endef

define print_success
	@if [ -t 1 ]; then printf '\033[1;32m%s\033[0m\n' "$(1)"; else printf '%s\n' "$(1)"; fi
endef

define print_error
	@if [ -t 2 ]; then printf '\033[1;31m%s\033[0m\n' "$(1)" >&2; else printf '%s\n' "$(1)" >&2; fi
endef

.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

help:
	@echo "星火NPU常用命令："
	@echo "  make lint       Verilator检查全部Verilog-2005 RTL"
	@echo "  make vectors    用Python golden model生成批量测试向量"
	@echo "  make sim        生成向量、构建并运行Verilator仿真"
	@echo "  make sva-test   用Verilator运行NPU1.2周期级SVA"
	@echo "  make test       运行Python、Verilator批量仿真和SVA"
	@echo "  make ppa-check  检查本地ICS55 PPA依赖"
	@echo "  make ppa        运行现有ICS55 PPA流程"
	@echo "  make clean-sim  删除功能仿真生成物"
	@echo "  make clean      删除全部build生成物"
	@echo
	@echo "随机测试参数：TEST_COUNT=$(TEST_COUNT) TEST_SEED=$(TEST_SEED)"

# expected只由Python golden model计算，生成物统一写入build/。
vectors: $(GOLDEN_MODEL) $(VECTOR_GENERATOR)
	@mkdir -p "$(SIM_BUILD_DIR)"
	@$(PYTHON) "$(VECTOR_GENERATOR)" \
		--count "$(TEST_COUNT)" --seed "$(TEST_SEED)" --output "$(VECTOR_FILE)"

# 使用统一filelist构建C++17 Verilator模型；完整工具输出保存到日志。
$(SIM_BINARY): $(RTL_FILELIST) $(RTL_FILES) $(SIM_CPP) Makefile
	@mkdir -p "$(VERILATOR_DIR)" "$(SIM_BUILD_DIR)"
	@echo "Building Verilator model..."
	@if ! $(VERILATOR) --cc --exe --build \
		-Wall --language 1364-2005 \
		--top-module "$(TOP)" \
		--Mdir "$(VERILATOR_DIR)" \
		-CFLAGS "-std=c++17" \
		-f "$(RTL_FILELIST)" "$(SIM_CPP)" > "$(BUILD_LOG)" 2>&1; then \
		if [ -t 2 ]; then printf '\033[1;31m%s\033[0m\n' "ERROR: Verilator构建失败，日志末尾如下：" >&2; else printf '%s\n' "ERROR: Verilator构建失败，日志末尾如下：" >&2; fi; \
		tail -n 80 "$(BUILD_LOG)"; \
		exit 1; \
	fi
	$(call print_success,Verilator model ready: $(SIM_BINARY))

sim: vectors $(SIM_BINARY)
	@"$(SIM_BINARY)" "$(VECTOR_FILE)"

python-test: $(GOLDEN_MODEL) $(PYTHON_TESTS)
	$(call print_info,Running Python golden model tests...)
	@$(PYTHON) -m unittest discover -s tests -v
	$(call print_success,PYTHON GOLDEN MODEL TESTS PASSED)

sva-test: $(RTL_FILELIST) $(RTL_FILES) verification/XingHuo_NPU_assertions.sv verification/XingHuo_NPU_sva_tb.sv
	@mkdir -p "$(SVA_BUILD_DIR)"
	$(call print_info,Running NPU1.2 SVA test...)
	@if ! $(VERILATOR) --binary --assert --timing -Wall -Wno-BLKSEQ \
		-Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET \
		--top-module XingHuo_NPU_sva_tb --Mdir "$(SVA_BUILD_DIR)/obj" \
		-f "$(RTL_FILELIST)" verification/XingHuo_NPU_assertions.sv \
		verification/XingHuo_NPU_sva_tb.sv > "$(SVA_LOG)" 2>&1; then \
		if [ -t 2 ]; then printf '\033[1;31m%s\033[0m\n' "ERROR: SVA构建失败，日志末尾如下：" >&2; else printf '%s\n' "ERROR: SVA构建失败，日志末尾如下：" >&2; fi; tail -n 80 "$(SVA_LOG)"; exit 1; \
	fi
	@if ! "$(SVA_BUILD_DIR)/obj/VXingHuo_NPU_sva_tb" >> "$(SVA_LOG)" 2>&1; then \
		if [ -t 2 ]; then printf '\033[1;31m%s\033[0m\n' "ERROR: SVA仿真失败，日志末尾如下：" >&2; else printf '%s\n' "ERROR: SVA仿真失败，日志末尾如下：" >&2; fi; tail -n 80 "$(SVA_LOG)"; exit 1; \
	fi
	@grep -q "NPU1.2 SVA TEST PASS" "$(SVA_LOG)"
	$(call print_success,NPU1.2 SVA TEST PASSED)

test: python-test sim sva-test
	$(call print_success,ALL TESTS AND VERIFICATION PASSED)

# lint只读取filelists/rtl.f中的正式RTL，不包含仿真、reference或build。
lint: $(RTL_FILELIST) $(RTL_FILES)
	@mkdir -p "$(dir $(LINT_LOG))"
	$(call print_info,Linting Verilog-2005 RTL...)
	@if ! $(VERILATOR) --lint-only -Wall --language 1364-2005 \
		--top-module "$(TOP)" -f "$(RTL_FILELIST)" > "$(LINT_LOG)" 2>&1; then \
		if [ -t 2 ]; then printf '\033[1;31m%s\033[0m\n' "ERROR: Verilator lint失败，日志末尾如下：" >&2; else printf '%s\n' "ERROR: Verilator lint失败，日志末尾如下：" >&2; fi; \
		tail -n 80 "$(LINT_LOG)"; \
		exit 1; \
	fi
	$(call print_success,RTL LINT PASSED (log: $(LINT_LOG)))

ppa-check:
	@$(MAKE) -C ppa check

ppa:
	@$(MAKE) -C ppa ppa

clean-sim:
	@rm -rf "$(SIM_BUILD_DIR)" "$(VERILATOR_DIR)" "$(BUILD_DIR)/lint" "$(SVA_BUILD_DIR)"

clean:
	@rm -rf "$(BUILD_DIR)"

.PHONY: help vectors sim python-test sva-test test lint ppa-check ppa clean-sim clean
