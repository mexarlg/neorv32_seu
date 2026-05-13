#==============================================================================
# File: waves.do
#
# Description:
#   Waveform configuration for ModelSim.
#   Signals are grouped logically. General viewer settings are applied at the end.
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# CLOCK / RESET
#===========================================================================
add wave -divider "CLOCK / RESET" \
    -color white -radix binary sim:/tb_tmr_register/clk \
    -color white -radix binary sim:/tb_tmr_register/rst 


#===========================================================================
# INPUTS
#===========================================================================
add wave -divider "INPUTS" \
    -color green -radix binary sim:/tb_tmr_register/en \
    -color green -radix binary sim:/tb_tmr_register/d_in


#===========================================================================
# OUTPUTS
#===========================================================================
add wave -divider "OUTPUTS" \
    -color cyan -radix binary sim:/tb_tmr_register/q_out \
    -color cyan -radix binary sim:/tb_tmr_register/err_out 



add wave -divider "INTERNAL BANKS (DUT)" \
    -color yellow -radix hex sim:/tb_tmr_register/DUT/reg_a \
    -color yellow -radix hex sim:/tb_tmr_register/DUT/reg_b \
    -color yellow -radix hex sim:/tb_tmr_register/DUT/reg_c



#==============================================================================
# GENERAL WAVEFORM VIEWER SETTINGS
#==============================================================================

# Column widths
configure wave -namecolwidth 200
configure wave -valuecolwidth 60
configure wave -signalnamewidth 1
# Timeline units
configure wave -timelineunits ns
# Restore initial zoom
WaveRestoreZoom {0 ns} {500 us}


#==============================================================================
# END OF FILE
#==============================================================================