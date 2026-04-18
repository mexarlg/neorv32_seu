#!/usr/bin/env bash
# =============================================================================
# compile_neorv32.sh
# Simple compile, upload and monitor script for NEORV32
#
# FIRST TIME ONLY — make executable:
#   chmod +x compile_neorv32.sh
#
# USAGE:
#   ./compile_neorv32.sh                  — runs default example (hello_world)
#   ./compile_neorv32.sh demo_blink_led   — runs a specific example from sw/example/
#
# If errors after editing on Windows, run in WSL:
#   sed -i 's/\r//' compile_neorv32.sh
# =============================================================================
#
#   PROCEDURE TO COMPILE AND RUN A C PROGRAM — EVERY SESSION
#
#   1) CONNECT CABLES:
#      - USB Micro-B → J13 (programs FPGA, powers board)
#      - PmodUSBUART → Pmod JB (UART communication)
#      - JTAG-HS2   → Pmod JD (optional, for GDB debugging)
#
#   2) ATTACH USB TO WSL2 — once per session in PowerShell as Administrator:
#      usbipd list                          (find BUSID of PmodUSBUART, VID 0403:6001)
#      usbipd attach --wsl --busid 4-3      (replace 4-3 with your actual BUSID)
#      ls /dev/ttyUSB*                      (verify it appeared in WSL2)
#
#   3) PROGRAM THE FPGA — once per session in Vivado:
#      Open Hardware Manager → Auto Connect → Program Device
#      Select the .bit file from build/neorv32_zybo_z7/neorv32_zybo_z7.runs/impl_1/
#      Verify green DONE LED lights up on the Zybo
#
#   4) GO TO PROJECT ROOT in WSL2:
#      cd /mnt/c/Users/aldor/Desktop/rp_riscv/neorv32_seu
#
#   5) PRESS BTN0 on the Zybo to reset the CPU
#
#   6) RUN THIS SCRIPT:
#      ./compile_neorv32.sh hello_world
#   
#   Useful for opening minicom:
#   minicom -D /dev/ttyUSB0 -b 19200
#   (If memory is changed on rtl top, change also common.mk)
#
# =============================================================================
 
# -----------------------------------------------------------------------------
# User configuration — edit these if your setup changes
# -----------------------------------------------------------------------------
 
# Default example to run if no argument is given
DEFAULT_EXAMPLE="hello_world"
 
# Serial port for UART (check with: ls /dev/ttyUSB*)
PORT="/dev/ttyUSB0"
 
# Baud rate — must match NEORV32 bootloader (always 19200 for v1.11.6)
BAUD="19200"
 
# Path to sw/ folder — script lives in project root alongside sw/
SW_DIR="$(dirname "$0")/sw"
 
# -----------------------------------------------------------------------------
# Script — no need to edit below this line
# -----------------------------------------------------------------------------
 
EXAMPLE=${1:-$DEFAULT_EXAMPLE}
 
# Fix serial port permissions
echo ">>> Fixing serial port permissions..."
sudo chmod 666 $PORT
 
# Verify serial port exists
if [ ! -e "$PORT" ]; then
    echo "ERROR: Serial port $PORT not found"
    echo "       Run in PowerShell as Administrator: usbipd attach --wsl --busid 4-3"
    exit 1
fi
 
# Compile
echo ">>> Compiling $EXAMPLE..."
cd "$SW_DIR/example/$EXAMPLE" || {
    echo "ERROR: Example '$EXAMPLE' not found in $SW_DIR/example/"
    echo "       Available examples:"
    ls "$SW_DIR/example/"
    exit 1
}
 
# RISCV_PREFIX and MARCH are now set correctly in sw/common/common.mk
# No need to override them here
make clean_all exe || { echo "ERROR: Compilation failed"; exit 1; }
 
# Verify signature (must be feca8847 for v1.11.6)
SIG=$(xxd neorv32_exe.bin | head -1 | awk '{print $2$3}')
if [ "$SIG" != "feca8847" ]; then
    echo "WARNING: Unexpected binary signature: $SIG (expected feca8847 for v1.11.6)"
    echo "         The bootloader may reject this binary"
fi
 
# Upload
echo ">>> Uploading to NEORV32..."
../../image_gen/uart_upload.sh $PORT neorv32_exe.bin || {
    echo "ERROR: Upload failed"
    echo "       Press BTN0 to reset the board and try again"
    exit 1
}
 
# Open serial monitor
echo ">>> Opening serial monitor (Ctrl+A then X to exit)..."
minicom -D $PORT -b $BAUD