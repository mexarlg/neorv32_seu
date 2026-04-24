#!/usr/bin/env bash
# =============================================================================
# compile_neorv32.sh
# Compile, upload, and monitor script for NEORV32
#
# FIRST TIME ONLY — make executable:
#   chmod +x compile_neorv32.sh
#
# USAGE:
#   ./compile_neorv32.sh                  # runs default example (hello_world)
#   ./compile_neorv32.sh demo_blink_led   # runs a specific example
#
# =============================================================================

set -e  # Exit immediately if a command fails


RED='\033[31m'
BLUE1='\033[1;34m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
RESET='\033[0m'
YELLOW='\033[1;33m'
RED1='\033[1;31m'
# Add spacing before banner
echo -e "\n\n\n"

echo -e "${RED} ##        ##   ##   ##    ${RESET}"
echo -e "${MAGENTA} ##     ##   #########   ########    ########   ##      ##   ########    ########     ##      ################  ${RESET}"
echo -e "${BLUE}####    ##  ##          ##      ##  ##      ##  ##      ##  ##      ##  ##      ##    ##    ####            ####${RESET}"
echo -e "${RED}## ##   ##  ##          ##      ##  ##      ##  ##      ##          ##         ##     ##      ##   ######   ##  ${RESET}"
echo -e "${RED}##  ##  ##  #########   ##      ##  #########   ##      ##      #####        ##       ##    ####   ######   ####${RESET}"
echo -e "${CYAN}##   ## ##  ##          ##      ##  ##     ##    ##    ##           ##     ##         ##      ##   ######   ##  ${RESET}"
echo -e "${MAGENTA}##    ####  ##          ##      ##  ##      ##    ##  ##    ##      ##   ##           ##    ####            ####${RESET}"
echo -e "${BLUE}##     ##    #########   ########   ##       ##     ##       ########   ##########    ##      ################  ${RESET}"
echo -e "${RED}                                                                                      ##        ##   ##   ##    ${RESET}"

# -----------------------------------------------------------------------------
# Default configuration
# -----------------------------------------------------------------------------


DEFAULT_EXAMPLE="hello_world"
#DEFAULT_EXAMPLE="demo_blink_led"
#DEFAULT_EXAMPLE="coremark"
BAUD="19200"

# -----------------------------------------------------------------------------
# Detect FTDI serial port
# -----------------------------------------------------------------------------

PORT=$(ls /dev/serial/by-id/*FTDI* 2>/dev/null | head -n 1)

if [ -z "$PORT" ]; then
  echo -e "${RED}ERROR: No FTDI serial port found."
  exit 1
fi

echo -e "${YELLOW}Using UART port: $PORT${RESET}"

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/sw"
UPLOAD_SCRIPT="$SCRIPT_DIR/image_gen/uart_upload.sh"
# -----------------------------------------------------------------------------
# Select example (use default if no argument provided)
# -----------------------------------------------------------------------------

EXAMPLE=${1:-$DEFAULT_EXAMPLE}

# -----------------------------------------------------------------------------
# Ensure port access permissions
# -----------------------------------------------------------------------------

echo -e "${RED1}>>> Setting serial port permissions...${RESET}"
sudo chmod 666 "$PORT"

# -----------------------------------------------------------------------------
# Open serial monitor
# -----------------------------------------------------------------------------

echo -e "${BLUE1}>>> Opening serial monitor in a new terminal...${RESET}"
gnome-terminal -- bash -c "
picocom -b $BAUD $PORT

STATUS=\$?

if [ \$STATUS -ne 0 ]; then
  echo '>>> UART error detected, resetting port...'
  fuser -k \"$PORT\" 2>/dev/null || true
fi

exec bash
"

sleep 5

echo -e "\n"
echo -e "${RED1}>>> Please implement the bitstream or reset the CPU within 15 seconds.${RESET}"

sleep 15

echo -e "${BLUE1}>>> Compiling example: $EXAMPLE${RESET}";

cd "$SCRIPT_DIR/example/$EXAMPLE/" || { echo "ERROR: Example not found"; exit 1; };

make clean_all exe;

echo -e "${CYAN}>>> Compilation done${RESET}";

echo -e "${BLUE1}>>> Uploading executable...${RESET}";

bash "$UPLOAD_SCRIPT" "$PORT" neorv32_exe.bin;

echo -e "${CYAN}>>> Upload done${RESET}";


# -----------------------------------------------------------------------------
# Send execution command
# -----------------------------------------------------------------------------

echo -e "${YELLOW}>>> Sending start command...${RESET}"
printf "e" > "$PORT"

# -----------------------------------------------------------------------------
# End of script
# -----------------------------------------------------------------------------


