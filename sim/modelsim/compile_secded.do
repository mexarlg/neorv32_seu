#==============================================================================
# File: compile_secded.do
#
# Description:
#   Compiles all RTL and testbench files into the ModelSim work library.
#
# Usage:
#   do compile_secded.do
#
#==============================================================================


echo "--------------------------------------------"
echo "Compiling design"
echo "--------------------------------------------"


#------------------------------------------------------------------------------
# Create work library
#------------------------------------------------------------------------------

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work


#------------------------------------------------------------------------------
# Compile RTL files
#------------------------------------------------------------------------------

echo "Compiling RTL..."

vcom -2008 ../../rtl/seu/neorv32_secded_encoder.vhd
vcom -2008 ../../rtl/seu/neorv32_secded_decoder.vhd

#------------------------------------------------------------------------------
# Compile Testbench files
#------------------------------------------------------------------------------

echo "Compiling Testbench..."

vcom -2008 ../tb/tb_neorv32_secded.vhd


echo "--------------------------------------------"
echo "Compilation finished"
echo "--------------------------------------------"