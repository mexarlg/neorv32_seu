#!/usr/bin/env bash
# =============================================================================
# start_openocd.sh
# Start an OpenOCD session for the NEORV32 on the Zybo Z7-20
#
# PREREQUISITES:
#   - FPGA programmed with OCD-enabled NEORV32 bitstream
#   - JTAG probe (FTDI FT2232H or similar) connected to Pmod JD:
#       JD1 (T14) = TCK
#       JD2 (T15) = TDI
#       JD3 (P14) = TDO
#       JD4 (R14) = TMS
#       JD5       = GND
#   - JTAG probe USB forwarded to WSL2:
#       usbipd attach --wsl --busid X   (PowerShell as Administrator)
#
# USAGE:
#   chmod +x start_openocd.sh
#   ./start_openocd.sh
#
#   Leave this terminal open. OpenOCD runs as a server.
#   Connect GDB from a second terminal.
# =============================================================================

# Path to the NEORV32 OpenOCD config — adjust if your project layout differs
NEORV32_OPENOCD_CFG="sw/openocd/openocd_neorv32.cfg"

# Check the config file exists
if [ ! -f "$NEORV32_OPENOCD_CFG" ]; then
    echo "ERROR: Cannot find $NEORV32_OPENOCD_CFG"
    echo "Run this script from the root of your project directory."
    exit 1
fi

echo "============================================================"
echo " Starting OpenOCD for NEORV32"
echo " Config: $NEORV32_OPENOCD_CFG"
echo " GDB port: 3333"
echo " Telnet port: 4444"
echo "============================================================"
echo ""
echo "Waiting for JTAG connection..."
echo "Press Ctrl+C to stop OpenOCD."
echo ""

openocd -f "$NEORV32_OPENOCD_CFG"
