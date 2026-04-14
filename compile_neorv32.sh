#!/usr/bin/env bash
# =============================================================================
# compile_neorv32.sh
# Simple compile, upload and monitor script for NEORV32
#
# FIRST TIME ONLY! — make executable (on path):
#   chmod +x compile_neorv32.sh
#
# USAGE:
#   ./compile_neorv32.sh                  — runs default example (hello_world)
#   ./compile_neorv32.sh demo_blink_led   — runs a specific example from sw/examples
#
# If errors due edit on windows, apply in wsl: sed -i 's/\r//' compile_neorv32.sh
# =============================================================================
#
#   PROCEDURE TO COMPILE A C PROGRAM IN A SESSION
#
# 1) FPGA CABLES — connect programmer, uart and jtag (optional):
#
# 2) USB PORTS — Once per session in PowerShell as Administrator:
#   usbipd list  (on windows terminal)
#   usbipd attach --wsl --busid 4-3  (on windows terminal, check busid of uart - 6001)
#   ls /dev/ttyUSB*   (on wsl)
#
# 3) VIVADO SCRIPT — Once per session in VIVADO:
#   Go to tools and run TCL script
#   Select run_neorv32.tcl
#   Synthesis, implement and program bitstream
#
# 5) GO TO ROOT DIRECTORY OF NEORV32_SEU (Aldo, Olivier, Teresa)
#   cd /mnt/c/Users/aldor/Desktop/rp_riscv/neorv32_seu
# 
# 5) Restart neorv32 with btn0 and wait 10 seconds
#
# 6) RUN COMPILATION SCRIPT - compile_neorv32.sh (Check memory of c program < imem vhdl)
#   if first time, apply to make it executable: chmod +x compile_neorv32.sh
#   ./compile_neorv32.sh my_program
#
# =============================================================================

# -----------------------------------------------------------------------------
# User configuration — edit these if your setup changes
# -----------------------------------------------------------------------------

# Default example to run if no argument is given
DEFAULT_EXAMPLE="hello_world"

# Serial port for UART
PORT="/dev/ttyUSB0"

# RISC-V compiler prefix
PREFIX="riscv32-unknown-elf-"

# Baud rate for serial monitor (must match NEORV32 bootloader)
BAUD="19200"

# Path to sw/ folder relative to this script
SW_DIR="$(dirname "$0")/sw"

# -----------------------------------------------------------------------------
# Script — no need to edit below this line
# -----------------------------------------------------------------------------

EXAMPLE=${1:-$DEFAULT_EXAMPLE}

echo ">>> Fixing serial port permissions..."
sudo chmod 666 $PORT

echo ">>> Compiling $EXAMPLE..."
cd "$SW_DIR/example/$EXAMPLE" || { echo "ERROR: Example '$EXAMPLE' not found in $SW_DIR/example/"; exit 1; }
make RISCV_PREFIX=$PREFIX clean_all exe || { echo "ERROR: Compilation failed"; exit 1; }

echo ">>> Uploading to NEORV32..."
../../image_gen/uart_upload.sh $PORT neorv32_exe.bin || { echo "ERROR: Upload failed — press BTN0 to reset and try again"; exit 1; }

echo ">>> Opening serial monitor (Ctrl+A then X to exit)..."
minicom -D $PORT -b $BAUD
