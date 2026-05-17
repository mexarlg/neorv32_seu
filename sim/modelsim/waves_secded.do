#==============================================================================
# File: waves_secded.do
#
# Description:
#   Waveform configuration for the scrubber FSM testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_secded.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# Simulation
#===========================================================================
add wave -divider " Test "
add wave -color white  -radix unsigned sim:/tb_neorv32_secded/test_phase
add wave -color white  -radix binary sim:/tb_neorv32_secded/sim_done

#===========================================================================
# Encoder
#===========================================================================
add wave -divider " ENCODER "
add wave -color white  -radix hex sim:/tb_neorv32_secded/secded_enc_data_i
add wave -color white  -radix hex sim:/tb_neorv32_secded/secded_enc_code_o

#===========================================================================
# Decoder
#===========================================================================
add wave -divider " DECODER "
add wave -color white  -radix hex sim:/tb_neorv32_secded/secded_dec_data_i
add wave -color white  -radix hex sim:/tb_neorv32_secded/secded_dec_code_i
add wave -color white  -radix hex sim:/tb_neorv32_secded/secded_dec_data_o
add wave -color white  -radix binary sim:/tb_neorv32_secded/secded_stat_corrected_o
add wave -color white  -radix binary sim:/tb_neorv32_secded/secded_stat_detected_o
add wave -color white  -radix binary sim:/tb_neorv32_secded/secded_stat_no_error_o

#==============================================================================
# GENERAL WAVEFORM VIEWER SETTINGS
#==============================================================================
configure wave -namecolwidth 260
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1
configure wave -timelineunits ns
WaveRestoreZoom {0 ns} {1000 ns}

#==============================================================================
# END OF FILE
#==============================================================================