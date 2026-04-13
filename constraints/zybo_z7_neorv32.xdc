# =============================================================================
# zybo_z7_neorv32.xdc
# Pin constraints for NEORV32 (OCD setup) on the Digilent Zybo Z7-20
# Part: XC7Z020-1CLG400C
#
# Port-name convention must match your top-level entity exactly.
# All port names here correspond to the NEORV32 on_chip_debugger test setup
#
# ── SIGNAL MAPPING SUMMARY ──────────────────────────────────────────────────
#  clk_i        → PL 125 MHz oscillator         (K17)
#  rstn_i       → Push button BTN0 (active-high)(K18)
#  gpio_o[0:3]  → LEDs LD0-LD3                  (M14,M15,G14,D18)
#  gpio_o[4:7]  → Pmod JC pins 1-4              (V15,W15,T11,T10)
#  uart0_txd_o  → Pmod JB pin 2                 (W8)
#  uart0_rxd_i  → Pmod JB pin 3                 (U7)
#  jtag_tck_i   → Pmod JD pin 1                 (T14)
#  jtag_tdi_i   → Pmod JD pin 2                 (T15)
#  jtag_tdo_o   → Pmod JD pin 3                 (P14)
#  jtag_tms_i   → Pmod JD pin 4                 (R14)
#
# ── UART NOTE ────────────────────────────────────────────────────────────────
#  The Zybo Z7's USB-UART bridge is wired to the Zynq PS (MIO), NOT to the PL!
#  Therefore NEORV32 UART must go through a Pmod connector to a USB-serial
#  adapter (e.g. a FTDI Pmod).
#
# ── JTAG NOTE ────────────────────────────────────────────────────────────────
#  The NEORV32 OCD uses its OWN JTAG port (not the Digilent USB-JTAG chain).
#  Use a separate JTAG probe (e.g. FTDI-based) connected to
#  Pmod JD. The Digilent USB connector is only used to program the bitstream.
#
# ── BTN NOTE ────────────────────────────────────────────────────────────────
#  BTN are active-high, should invert on top wrapper for rstn_i.
#
# =============================================================================

# -----------------------------------------------------------------------------
# Clock — 125 MHz PL oscillator

# The Zybo Z7 provides a 125 MHz clock from the Ethernet PHY to PL pin K17.
# Use a MMCM in your top wrapper if you need a different frequency.
set_property -dict { PACKAGE_PIN K17  IOSTANDARD LVCMOS33 } [get_ports { clk_i }]
create_clock -name sys_clk -period 8.000 -waveform {0.000 4.000} [get_ports { clk_i }]

# -----------------------------------------------------------------------------
# BTN0 is active high. RSTN of NEORV32 is active low. This is dealt on top wrapper
set_property -dict { PACKAGE_PIN K18  IOSTANDARD LVCMOS33 } [get_ports { btn0 }]    ;# BTN0

# -----------------------------------------------------------------------------
# GPIO LED OUTPUTS: LD0-LD3 + 4 PMOD JC
# Mapped to 4 on board LEDs (LD0–LD3) + 4 Pmod JC pins
# LEDs are anode connected through 330 Ω resistors so logic HIGH = LED ON.

# Onboard LEDs
set_property -dict { PACKAGE_PIN M14  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[0] }]   ;# LED0
set_property -dict { PACKAGE_PIN M15  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[1] }]   ;# LED1
set_property -dict { PACKAGE_PIN G14  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[2] }]   ;# LED2
set_property -dict { PACKAGE_PIN D18  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[3] }]   ;# LED3

# Pmod JC — pins 1-4 (upper row, P1 is top right), useful for ILAS (SEU injection)
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[4] }]   ;# PIN1 JC (TOP RIGHT CORNER)
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[5] }]   ;# PIN2 JC
set_property -dict { PACKAGE_PIN T11  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[6] }]   ;# PIN3 JC
set_property -dict { PACKAGE_PIN T10  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[7] }]   ;# PIN4 JC

# -----------------------------------------------------------------------------
# UART-USB Converter JB: (blue card) 

# Ports of blue converter: (mark "1" on board = Port 1, mark "J2" = Port 6)
# "1" RTS Ready to Send
# "2" RXD Receive
# "3" TXD Transmit
# "4" CTS Clear to Send
# "5" GND Ground
# "6" SYS3V3 Power Supply (3.3V)

# Jumper switch (blue cap) should be attached to LCL if FPGA is powered on its own!!! (It is!)
# LED1 of blue converter indicates data transfer from Usb to uart (FPGA). 
# LED2 of blue converter indicates data transfer from uart (FPGA) to Usb.

# Pin 1 to 6 of blue converter should be connected to Pin 1 to 6 of PMOD JB (P1 is "square", P6 is "3.3V")
# This is connecting the blue converter onto the TOP ROW of PMOD JB (with blue cap of converter positioned up!)

# Port 2 of converter (RXD) should be connected to TX of uart (FPGA)
# Port 3 of converter (TXD) should be connected to RX of uart (FPGA)

set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports { uart0_txd_o }]  ;# JB pin 2 → W8
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports { uart0_rxd_i }]  ;# JB pin 3 → U7

# -----------------------------------------------------------------------------
# JTAG — Pmod JD (High-Speed connector) (Top row)
# Used for NEORV32 On-Chip Debugger (separate from Digilent USB programming JTAG)
#
# Standard JTAG wiring:
#   JD1 (T14) jtag_tck_i → probe TCK
#   JD2 (T15) jtag_tdi_i → probe TDI
#   JD3 (P14) jtag_tdo_o → probe TDO
#   JD4 (R14) jtag_tms_i → probe TMS
#   JD5       GND        → probe GND
#   JD6       3V3        → probe VTREF
#
# IMPORTANT: The JTAG TCK pin must have its own timing constraint (1-10 MHz).
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T14  IOSTANDARD LVCMOS33 } [get_ports { jtag_tck_i }]  ;# Pin 1 PMOD JD
set_property -dict { PACKAGE_PIN T15  IOSTANDARD LVCMOS33 } [get_ports { jtag_tdi_i }]  ;# Pin 2 PMOD JD
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports { jtag_tdo_o }]  ;# Pin 3 PMOD JD
set_property -dict { PACKAGE_PIN R14  IOSTANDARD LVCMOS33 } [get_ports { jtag_tms_i }]  ;# Pin 4 PMOD JD

# JTAG clock — create as a separate clñ, asynchronous to sys_clk.
# 10 MHz maximum is safe; OpenOCD default is typically 1-4 MHz.
create_clock -name jtag_tck -period 100.000 [get_ports { jtag_tck_i }]

# Declare the two clock domains asynchronous
set_clock_groups -asynchronous -group [get_clocks sys_clk] \
                               -group [get_clocks jtag_tck]

# -----------------------------------------------------------------------------
# Optional: Push buttons BTN1-BTN3 (useful for SW-controlled test triggers)
# -----------------------------------------------------------------------------
# set_property -dict { PACKAGE_PIN P16  IOSTANDARD LVCMOS33 } [get_ports { btn1_i }]
# set_property -dict { PACKAGE_PIN K19  IOSTANDARD LVCMOS33 } [get_ports { btn2_i }]
# set_property -dict { PACKAGE_PIN Y16  IOSTANDARD LVCMOS33 } [get_ports { btn3_i }]

# -----------------------------------------------------------------------------
# Optional: Slide switches — can feed gpio_i for runtime configuration
# -----------------------------------------------------------------------------
# set_property -dict { PACKAGE_PIN G15  IOSTANDARD LVCMOS33 } [get_ports { sw_i[0] }]
# set_property -dict { PACKAGE_PIN P15  IOSTANDARD LVCMOS33 } [get_ports { sw_i[1] }]
# set_property -dict { PACKAGE_PIN W13  IOSTANDARD LVCMOS33 } [get_ports { sw_i[2] }]
# set_property -dict { PACKAGE_PIN T16  IOSTANDARD LVCMOS33 } [get_ports { sw_i[3] }]

# -----------------------------------------------------------------------------
# Timing exceptions — false paths on asynchronous inputs
# Buttons and switches are asynchronous; prevent the timing analyser from
# flagging them as timing violations.
# -----------------------------------------------------------------------------
set_false_path -from [get_ports { btn0 }]
# set_false_path -from [get_ports { btn1_i }]   ;# uncomment when used
# set_false_path -from [get_ports { sw_i[*] }]  ;# uncomment when used

# -----------------------------------------------------------------------------
# Bitstream configuration — use the Digilent USB programmer (JTAG chain pos 1)
# -----------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS    TRUE  [current_design]
set_property CONFIG_VOLTAGE                3.3   [current_design]
set_property CFGBVS                        VCCO  [current_design]
