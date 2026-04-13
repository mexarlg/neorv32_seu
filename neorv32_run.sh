#!/usr/bin/env bash
# =============================================================================
# neorv32_run.sh
# Simple compile, upload and monitor script for NEORV32
#
# FIRST TIME ONLY — make executable:
#   chmod +x neorv32_run.sh
#
# USAGE:
#   ./neorv32_run.sh                  — runs default example (hello_world)
#   ./neorv32_run.sh demo_blink_led   — runs a specific example
#
# BEFORE RUNNING — do this once per session in PowerShell as Administrator:
#   usbipd attach --wsl --busid 4-3
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
