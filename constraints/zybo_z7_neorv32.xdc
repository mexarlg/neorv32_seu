# =============================================================================
# zybo_z7_neorv32.xdc
# Pin constraints for NEORV32 (OCD setup) on the Digilent Zybo Z7-20
# Part: XC7Z020-1CLG400C
#
# Port-name convention must match your top-level entity exactly.
# All port names here correspond to the NEORV32 on_chip_debugger test setup
# naming convention.  Rename if your wrapper uses different signal names.
#
# ── SIGNAL MAPPING SUMMARY ──────────────────────────────────────────────────
#  clk_i        → PL 125 MHz oscillator         (K17)
#  rstn_i       → Push button BTN0 (active-low) (K18)
#  gpio_o[0:3]  → LEDs LD0-LD3                  (M14,M15,G14,D18)
#  gpio_o[4:7]  → Pmod JA pins 1-4              (N15,L14,K16,K14)
#  uart0_txd_o  → Pmod JB pin 1                 (T20)
#  uart0_rxd_i  → Pmod JB pin 2                 (U20)
#  jtag_tck_i   → Pmod JD pin 1                 (T14)
#  jtag_tdi_i   → Pmod JD pin 2                 (T15)
#  jtag_tdo_o   → Pmod JD pin 3                 (P14)
#  jtag_tms_i   → Pmod JD pin 4                 (R14)
#
# ── UART NOTE ────────────────────────────────────────────────────────────────
#  The Zybo Z7's USB-UART bridge is wired to the Zynq PS (MIO), NOT to the PL.
#  Therefore NEORV32 UART must go through a Pmod connector to a USB-serial
#  adapter (e.g. a FTDI Pmod, or any 3.3V USB-TTL cable):
#    Pmod JB pin 1 (T20) → adapter RX
#    Pmod JB pin 2 (U20) → adapter TX
#    Pmod JB pin 5 (GND) → adapter GND
#
# ── JTAG NOTE ────────────────────────────────────────────────────────────────
#  The NEORV32 OCD uses its OWN JTAG port (not the Digilent USB-JTAG chain).
#  Use a separate JTAG probe (e.g. FTDI-based, J-Link, or Segger) connected to
#  Pmod JD.  The Digilent USB connector is only used to program the bitstream.
#
#  OpenOCD config example (neorv32.cfg):
#    adapter driver ftdi
#    ftdi vid_pid 0x0403 0x6010
#    transport select jtag
#    set NEORV32_TAP_IDCODE 0x0cafe001
#    source [find target/neorv32.cfg]
# =============================================================================

# -----------------------------------------------------------------------------
# Clock — 125 MHz PL oscillator
# The Zybo Z7 provides a 125 MHz clock from the Ethernet PHY to PL pin K17.
# NEORV32 can run at this frequency on the -1 speed grade without issues.
# Use a MMCM in your top wrapper if you need a different frequency.
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN K17  IOSTANDARD LVCMOS33 } [get_ports { clk_i }]
create_clock -name sys_clk -period 8.000 -waveform {0.000 4.000} [get_ports { clk_i }]

# -----------------------------------------------------------------------------
# Reset — BTN0 (active-low in NEORV32; button drives HIGH when pressed,
# so invert in your top-level wrapper or use BTN1 mapped to active-high and
# invert in the XDC with a PULLDOWN if needed).
# The NEORV32 rstn_i is ACTIVE LOW — pressing BTN0 should bring the line low.
# Easiest approach: tie rstn_i = ~btn0 in your wrapper.
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN K18  IOSTANDARD LVCMOS33 } [get_ports { btn0 }]
# Note: BTN0 is active-high on board. If rstn_i is wired directly (not inverted
# in the wrapper), the CPU will be in reset whenever NO button is pressed.
# It is STRONGLY recommended to invert in the wrapper:
#   rstn_i <= not btn0;  -- CPU runs normally; press BTN0 to reset.

# -----------------------------------------------------------------------------
# GPIO outputs — mapped to 4 on-board LEDs (LD0–LD3) + 4 Pmod JA pins
# gpio_o is 64-bit in neorv32_top but only lower 8 bits are used here.
# LEDs are anode-connected through 330 Ω resistors — logic HIGH = LED ON.
# -----------------------------------------------------------------------------
# On-board LEDs
set_property -dict { PACKAGE_PIN M14  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[0] }]
set_property -dict { PACKAGE_PIN M15  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[1] }]
set_property -dict { PACKAGE_PIN G14  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[2] }]
set_property -dict { PACKAGE_PIN D18  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[3] }]

# Pmod JA — pins 1-4 (upper row), useful as additional debug outputs
# (e.g. connect a logic analyser here for fault injection experiments)
set_property -dict { PACKAGE_PIN N15  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[4] }]
set_property -dict { PACKAGE_PIN L14  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[5] }]
set_property -dict { PACKAGE_PIN K16  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[6] }]
set_property -dict { PACKAGE_PIN K14  IOSTANDARD LVCMOS33 } [get_ports { gpio_o[7] }]

# -----------------------------------------------------------------------------
# UART0 — Pmod JB (Hi-Speed connector, bank 34)
# Connect a 3.3V USB-serial adapter here.
# Pmod JB pinout (top row): JB1=T20, JB2=U20, JB3=V20, JB4=W20
#                             JB7=Y18, JB8=Y19, JB9=W18, JB10=W19
#
# Wiring to a USB-TTL adapter:
#   JB1 (T20) uart0_txd_o → adapter RXD
#   JB2 (U20) uart0_rxd_i → adapter TXD
#   JB5       GND          → adapter GND
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T20  IOSTANDARD LVCMOS33 } [get_ports { uart0_txd_o }]
set_property -dict { PACKAGE_PIN U20  IOSTANDARD LVCMOS33 } [get_ports { uart0_rxd_i }]

# -----------------------------------------------------------------------------
# JTAG — Pmod JD (Hi-Speed connector, bank 34)
# Used for NEORV32 On-Chip Debugger (separate from Digilent USB programming JTAG)
# Pmod JD pinout (top row): JD1=T14, JD2=T15, JD3=P14, JD4=R14
#                             JD7=U14, JD8=U15, JD9=V17, JD10=V18
#
# Standard JTAG wiring:
#   JD1 (T14) jtag_tck_i → probe TCK
#   JD2 (T15) jtag_tdi_i → probe TDI
#   JD3 (P14) jtag_tdo_o → probe TDO
#   JD4 (R14) jtag_tms_i → probe TMS
#   JD5       GND          → probe GND
#   JD6       3V3          → probe VTREF (if required)
#
# IMPORTANT: The JTAG TCK pin must have its own timing constraint (below).
#            The OCD JTAG runs much slower than the system clock (typ. 1-10 MHz).
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN T14  IOSTANDARD LVCMOS33 } [get_ports { jtag_tck_i }]
set_property -dict { PACKAGE_PIN T15  IOSTANDARD LVCMOS33 } [get_ports { jtag_tdi_i }]
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports { jtag_tdo_o }]
set_property -dict { PACKAGE_PIN R14  IOSTANDARD LVCMOS33 } [get_ports { jtag_tms_i }]

# JTAG clock — create as a separate clock domain, asynchronous to sys_clk.
# 10 MHz maximum is safe; OpenOCD default is typically 1-4 MHz.
create_clock -name jtag_tck -period 100.000 [get_ports { jtag_tck_i }]

# Declare the two clock domains asynchronous to each other so the timing
# analyser does not try to find a path between them.
set_clock_groups -asynchronous -group [get_clocks sys_clk] \
                               -group [get_clocks jtag_tck]

# -----------------------------------------------------------------------------
# Optional: Push buttons (useful for SW-controlled test triggers)
# BTN0 is already used as reset above.
# BTN1–BTN3 are available for firmware-controlled test inputs.
# Uncomment and connect to gpio_i in your wrapper if needed.
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
set_false_path -from [get_ports { rstn_i }]
# set_false_path -from [get_ports { btn1_i }]   ;# uncomment when used
# set_false_path -from [get_ports { sw_i[*] }]  ;# uncomment when used

# -----------------------------------------------------------------------------
# Bitstream configuration — use the Digilent USB programmer (JTAG chain pos 1)
# -----------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS    TRUE  [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4     [current_design]
set_property CONFIG_VOLTAGE                3.3   [current_design]
set_property CFGBVS                        VCCO  [current_design]
