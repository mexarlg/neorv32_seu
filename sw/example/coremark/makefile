# Application makefile.

# Override the default CPU ISA — must match VHDL generics exactly
MARCH = rv32imc_zicsr_zifencei

# Override default optimization goal
EFFORT = -O3

# Add extended debug symbols
USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size
USER_FLAGS += \
-Wl,--defsym,__neorv32_rom_size=64k \
-Wl,--defsym,__neorv32_rom_base=0x00000000

# Adjust processor DMEM size — must match DMEM_SIZE generic in VHDL
USER_FLAGS += \
-Wl,--defsym,__neorv32_ram_size=32k \
-Wl,--defsym,__neorv32_ram_base=0x80000000

# Additional sources
APP_SRC += $(wildcard source/*.c)
APP_INC += -I include

# Set path to NEORV32 root directory
NEORV32_HOME ?= ../../..

# Include the main NEORV32 makefile
include $(NEORV32_HOME)/sw/common/common.mk