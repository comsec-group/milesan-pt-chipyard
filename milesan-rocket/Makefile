# Copyright 2022 Flavien Solt, ETH Zurich.
# Licensed under the General Public License, Version 3.0, see LICENSE for details.
# SPDX-License-Identifier: GPL-3.0-only

RESOURCEWRAPPER_TAG = rocket
DESIGN_NAME = rocket
# Used in the Modelsim infra.
VARIANT_ID = _rocket

REPLACE_BOOTROM = 0

TOP_MODULE = rocket_mem_top
VCD_REGEX = tb_top/i_dut/*

# WIRE_PC_TO_TOP = 1
# PC_TARGET_MODULE = IBuf
# PC_TARGET = io_pc
# PC_TARGET_T0 =  buf__pc_t0
# ADD_SHADOW_PC_RESET = 1
# BLOCK_MODULE_SIGNAL_T0_PAIRS = $(PC_TARGET_MODULE),$(PC_TARGET_T0)

DESIGN_CONFIG = MySmallVMRocketConfig

MILESAN_DIR := ${shell dirname ${shell pwd}}/milesan-rocket

include ../milesan-common/milesan-common.mk
