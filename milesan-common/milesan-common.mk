# Copyright 2022 Flavien Solt, ETH Zurich.
# Licensed under the General Public License, Version 3.0, see LICENSE for details.
# SPDX-License-Identifier: GPL-3.0-only

ifeq "" "$(MILESAN_ENV_SOURCED)"
$(error Please re-source env.sh first, in the meta repo, and run from there, not this repo. See README.md in the meta repo)
endif

PYTHON ?= python3
YOSYS ?= yosys
TOP_SOC = top_tiny_soc
TOP_EXECUTABLE_NAME = V$(TOP_SOC)

# For drfuzz
TOP_RESET_MEM = reset_wire_reset
TOP_RESET = reset
EXCLUDE_SIGNALS ?= clock,$(TOP_RESET),metaReset,clk_i,$(TOP_RESET_MEM)

TARGET_NAMES = vanilla drfuzz_mem drfuzz_mem_muxcov passthrough

# Path to the design verilog

DESIGN_VERILOG_ROOT = ../sims/verilator/generated-src/chipyard.TestHarness.$(DESIGN_CONFIG)/chipyard.TestHarness.$(DESIGN_CONFIG).top
PATH_TO_DESIGN_MEMS_VERILOG = $(DESIGN_VERILOG_ROOT).mems.v
PATH_TO_DESIGN_VERILOG = $(DESIGN_VERILOG_ROOT).v
PATH_TO_DESIGN_VERILOG_REPLACED_BOOTROM = generated/replaced_bootrom.sv
DESIGN_VERILOG_DEPENDENCIES=$(patsubst %,src/dependencies/%, ClockDividerN.sv EICG_wrapper.v IOCell.v plusarg_reader.v sram_behav_models.v)

ifeq ($(REPLACE_BOOTROM),0)
DESIGN_SOURCES_TO_INSTRUMENT = ../milesan-common/src/defines.v $(DESIGN_VERILOG_DEPENDENCIES) $(PATH_TO_DESIGN_MEMS_VERILOG) $(PATH_TO_DESIGN_VERILOG) generated/$(DESIGN_NAME)_axi_to_mem.v generated/$(DESIGN_NAME)_mem_top.v
else
DESIGN_SOURCES_TO_INSTRUMENT = ../milesan-common/src/defines.v $(DESIGN_VERILOG_DEPENDENCIES) $(PATH_TO_DESIGN_MEMS_VERILOG) $(PATH_TO_DESIGN_VERILOG_REPLACED_BOOTROM) generated/$(DESIGN_NAME)_axi_to_mem.v generated/$(DESIGN_NAME)_mem_top.v
endif

include $(MILESAN_DESIGN_PROCESSING_ROOT)/common/design.mk

# This target makes the design until the Yosys instrumentation. From there on, the Makefile can run in parallel for the various instrumentation targets.
before_instrumentation: generated/out/vanilla.sv

#
# 0. Generate the design sources sources
#

$(PATH_TO_DESIGN_VERILOG) $(PATH_TO_DESIGN_MEMS_VERILOG):
# The dash ignores errors, which is useful because sometimes the command fails at the Verilator stage, but we only need the intermediate Verilog result.
	- make -C ../sims/verilator CONFIG=$(DESIGN_CONFIG)

#
# 1. Swap the AXI SRAM out for an AXI to mem converter followed by a blackbox mem.
#

generated/$(DESIGN_NAME)_axi_to_mem.v: src/$(DESIGN_NAME)_axi_to_mem.sv | generated
	sv2v -E=UnbasedUnsized $< -w $@
# Add newline in the end of the file because sv2v does not.
	echo  >> $@

generated/$(DESIGN_NAME)_mem_top.v: src/$(DESIGN_NAME)_mem_top.sv | generated
	sv2v -E=UnbasedUnsized $< -w $@
# Add newline in the end of the file because sv2v does not.
	echo  >> $@

generated/out/vanilla.sv: $(DESIGN_SOURCES_TO_INSTRUMENT) | generated/out
	cat $^ > $@

generated/out/vanilla.sv.log: | generated/out
	touch $@


generated/out/passthrough_precompact.sv: $(MILESAN_YS)/passthrough.ys.tcl generated/out/vanilla.sv  | generated/out logs
	VERILOG_INPUT=$(word 2,$^) VERILOG_OUTPUT=$@ TOP_MODULE=$(TOP_MODULE) $(YOSYS) -c $< -l $@.log

generated/out/drfuzz_mem_precompact.sv: $(MILESAN_YS)/drfuzz.ys.tcl generated/out/vanilla.sv | generated/out logs
	DECOMPOSE_MEMORY=1 VERILOG_INPUT=$(word 2,$^) CELLIFT_EN=1 VERILOG_OUTPUT=$@ TOP_MODULE=$(TOP_MODULE) EXCLUDE_SIGNALS=$(EXCLUDE_SIGNALS)  WIRE_PC_TO_TOP=$(WIRE_PC_TO_TOP) PC_TARGET_MODULE=$(PC_TARGET_MODULE) PC_TARGET=$(PC_TARGET) VERBOSE=$(VERBOSE) $(YOSYS) -c $< -l $@.log


generated/out/drfuzz_mem_muxcov_precompact.sv: $(MILESAN_YS)/drfuzz.ys.tcl generated/out/vanilla.sv | generated/out logs
	DECOMPOSE_MEMORY=1 VERILOG_INPUT=$(word 2,$^) CELLIFT_EN=1 VERILOG_OUTPUT=$@ TOP_MODULE=$(TOP_MODULE) EXCLUDE_SIGNALS=$(EXCLUDE_SIGNALS)  WIRE_PC_TO_TOP=$(WIRE_PC_TO_TOP) PC_TARGET_MODULE=$(PC_TARGET_MODULE) PC_TARGET=$(PC_TARGET) VERBOSE=$(VERBOSE) MUXCOV_EN=1 INST_TOP=$(TOP_MODULE) $(YOSYS) -c $< -l $@.log


# compact targets
generated/out/drfuzz_mem.sv: generated/out/drfuzz_mem_precompact.sv| generated/out logs
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/expand_left_operand.py $< generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/expand_right_operand.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/compress_concats.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/divide_concat_into_subconcats.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/init_regs_with_zero.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/init_mems_with_zero.py generated/interm.sv generated/interm.sv

	cp generated/interm.sv $@
	# rm -f generated/interm.sv
	cp $<.log $@.log


# compact targets
generated/out/drfuzz_mem_muxcov.sv: generated/out/drfuzz_mem_muxcov_precompact.sv| generated/out logs
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/expand_left_operand.py $< generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/expand_right_operand.py $< generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/compress_concats.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/divide_concat_into_subconcats.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/init_regs_with_zero.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/init_mems_with_zero.py generated/interm.sv generated/interm.sv

	cp generated/interm.sv $@
	# rm -f generated/interm.sv
	cp $<.log $@.log



# compact targets
generated/out/passthrough.sv: generated/out/passthrough_precompact.sv| generated/out logs
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/init_regs_with_zero.py $< generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/init_mems_with_zero.py generated/interm.sv $@
	cp $<.log $@.log
	

# compact targets
generated/out/rfuzz_mem.sv: generated/out/rfuzz_mem_precompact.sv| generated/out logs
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/expand_left_operand.py $< generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/expand_right_operand.py $< generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/compress_concats.py generated/interm.sv generated/interm.sv
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/divide_concat_into_subconcats.py generated/interm.sv generated/interm.sv
	cat generated/interm.sv > $@
	rm -f generated/interm.sv
	cp $<.log $@.log

# MUX coverage instrumentation for passive rfuzz
generated/out/muxcov_mem.sv: generated/out/drfuzz_mem.sv
	cp $< $@
	cp $<.log $@.log


# Core files
CORE_FILES_NOTRACE=$(patsubst %,run_%_notrace.core, $(TARGET_NAMES))
$(CORE_FILES_NOTRACE): run_%.core: run_%.core.template
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/gen_corefiles.py $< $@

# Core files with trace enabled
CORE_FILES_TRACE=$(patsubst %,run_%_trace.core, $(TARGET_NAMES))
$(CORE_FILES_TRACE): run_%.core: run_%.core.template
	$(PYTHON) $(MILESAN_PYTHON_COMMON)/gen_corefiles.py $< $@

#
# 2. Replace the bootrom in Vanilla to have a dynamic ELF load.
#

$(PATH_TO_DESIGN_VERILOG_REPLACED_BOOTROM): $(PATH_TO_DESIGN_VERILOG) | generated
	$(PYTHON) ../milesan-common/scripts/replace_bootrom.py $^ $@

#
# 5. Build with Verilator through FuseSoC. The SRAM is added by FuseSoC directly.
#

# Phony targets

PREPARE_TARGETS_NOTRACE=$(patsubst %,prepare_%_notrace, $(TARGET_NAMES))
PREPARE_TARGETS_TRACE=$(patsubst %,prepare_%_trace, $(TARGET_NAMES))
PREPARE_TARGETS_TRACE_FST=$(patsubst %,prepare_%_trace_fst, $(TARGET_NAMES))
.PHONY: $(PREPARE_TARGETS_NOTRACE)  
$(PREPARE_TARGETS_NOTRACE) $(PREPARE_TARGETS_TRACE): prepare_%: build/run_%_0.1/default-verilator/$(TOP_EXECUTABLE_NAME)

# Actual targets

BUILD_TARGETS_NOTRACE=$(patsubst %,build/run_%_notrace_0.1/default-verilator/$(TOP_EXECUTABLE_NAME), $(TARGET_NAMES))
BUILD_TARGETS_TRACE=$(patsubst %,build/run_%_trace_0.1/default-verilator/$(TOP_EXECUTABLE_NAME), $(TARGET_NAMES))
BUILD_TARGETS_TRACE_FST=$(patsubst %,build/run_%_trace_fst_0.1/default-verilator/$(TOP_EXECUTABLE_NAME), $(TARGET_NAMES))

$(BUILD_TARGETS_NOTRACE): build/run_%_notrace_0.1/default-verilator/$(TOP_EXECUTABLE_NAME): generated/out/%.sv generated/out/%.sv.log run_%_notrace.core 
	rm -f fusesoc.conf
	fusesoc library add run_$*_notrace .
	fusesoc run --build run_$*_notrace
	cp $<.log $@.log
$(BUILD_TARGETS_TRACE): build/run_%_trace_0.1/default-verilator/$(TOP_EXECUTABLE_NAME): generated/out/%.sv generated/out/%.sv.log run_%_trace.core
	rm -f fusesoc.conf
	fusesoc library add run_$*_trace .
	fusesoc run --build run_$*_trace
	cp $<.log $@.log
$(BUILD_TARGETS_TRACE_FST): build/run_%_trace_fst_0.1/default-verilator/$(TOP_EXECUTABLE_NAME): generated/out/%.sv generated/out/%.sv.log run_%_trace_fst.core
	rm -f fusesoc.conf
	fusesoc library add run_$*_trace_fst .
	fusesoc run --build run_$*_trace_fst
	cp $<.log $@.log

#
# 6. Recompile, if only the sw has changed since the previous step.
#

RECOMPILE_TARGETS_NOTRACE=$(patsubst %,recompile_%_notrace, $(TARGET_NAMES))
RECOMPILE_TARGETS_TRACE=$(patsubst %,recompile_%_trace, $(TARGET_NAMES))
RECOMPILE_TARGETS_TRACE_FST=$(patsubst %,recompile_%_trace_fst, $(TARGET_NAMES))
RECOMPILE_TARGETS = $(RECOMPILE_TARGETS_NOTRACE) $(RECOMPILE_TARGETS_TRACE) $(RECOMPILE_TARGETS_TRACE_FST)

.PHONY: $(RECOMPILE_TARGETS)
$(RECOMPILE_TARGETS): recompile_%: build/run_%_0.1
	rm -f $</default-verilator/toplevel.o
	rm -f $</default-verilator/$(TOP_EXECUTABLE_NAME)
	rm -rf $</src/run_$*_0.1/dv
	rm -rf ./build/dv
	cp -r dv $</default-verilator/src/run_$*_0.1
	cp -r $(MILESAN_DESIGN_PROCESSING_ROOT)/common/dv ./build
	make -C $</default-verilator -j $(MILESAN_JOBS)

#
# 7. Rerun a simulation.
#

RERUN_TARGETS_NOTRACE=$(patsubst %,rerun_%_notrace, $(TARGET_NAMES))
RERUN_TARGETS_TRACE=$(patsubst %,rerun_%_trace, $(TARGET_NAMES))
RERUN_TARGETS_TRACE_FST=$(patsubst %,rerun_%_trace_fst, $(TARGET_NAMES))
RERUN_TARGETS = $(RERUN_TARGETS_NOTRACE) $(RERUN_TARGETS_TRACE) $(RERUN_TARGETS_TRACE_FST)

.PHONY: $(RERUN_TARGETS)
$(RERUN_TARGETS_TRACE) $(RERUN_TARGETS_TRACE_FST): | traces
$(RERUN_TARGETS): rerun_%: build/run_%_0.1/
	$</default-verilator/$(TOP_EXECUTABLE_NAME)

#
# 8. Run a simulation.
#

RUN_TARGETS_NOTRACE=$(patsubst %,run_%_notrace, $(TARGET_NAMES))
RUN_TARGETS_TRACE=$(patsubst %,run_%_trace, $(TARGET_NAMES))
RUN_TARGETS_TRACE_FST=$(patsubst %,run_%_trace_fst, $(TARGET_NAMES))
RUN_TARGETS = $(RUN_TARGETS_NOTRACE) $(RUN_TARGETS_TRACE) $(RUN_TARGETS_TRACE_FST)

$(RUN_TARGETS_TRACE) $(RUN_TARGETS_TRACE_FST): | traces
$(RUN_TARGETS): run_%: ./build/run_%_0.1/default-verilator/$(TOP_EXECUTABLE_NAME)
	cd build/run_$*_0.1/default-verilator && ./$(TOP_EXECUTABLE_NAME)

#
# Modelsim
#

# In the respective designs (Rocket and BOOM) MILESAN_DIR := ${shell dirname ${shell pwd}}
MODELSIM_PATH_TO_BUILD_TCL = $(MILESAN_DESIGN_PROCESSING_ROOT)/common/modelsim/modelsim_build.tcl

include $(MILESAN_DESIGN_PROCESSING_ROOT)/common/modelsim.mk
