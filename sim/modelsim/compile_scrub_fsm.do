#==============================================================================
# File: compile_scrub_fsm.do
#
# Description:
#   Compiles all RTL and testbench files into the ModelSim work library.
#
# Usage:
#   do compile_scrub_fsm.do
#
#==============================================================================


echo "--------------------------------------------"
echo "Compiling design"
echo "--------------------------------------------"


#------------------------------------------------------------------------------
# Create libraries
#------------------------------------------------------------------------------

if {[file exists work]} {
    vdel -lib work -all
}
if {[file exists neorv32]} {
    vdel -lib neorv32 -all
}

vlib work
vmap work work

vlib neorv32
vmap neorv32 neorv32


#------------------------------------------------------------------------------
# Compile RTL files into the neorv32 library
#------------------------------------------------------------------------------

echo "Compiling RTL..."

vcom -2008 -work neorv32 ../../rtl/core/neorv32_prim.vhd
vcom -2008 -work neorv32 ../../rtl/seu/neorv32_secded_encoder.vhd
vcom -2008 -work neorv32 ../../rtl/seu/neorv32_secded_decoder.vhd
vcom -2008 -work neorv32 ../../rtl/seu/neorv32_scrub_fsm.vhd


#------------------------------------------------------------------------------
# Compile Testbench files into work
#------------------------------------------------------------------------------

echo "Compiling Testbench..."

vcom -2008 -work work ../tb/tb_neorv32_scrub_fsm.vhd


echo "--------------------------------------------"
echo "Compilation finished"
echo "--------------------------------------------"