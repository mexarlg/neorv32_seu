#==============================================================================
# File: waves_scrub_fsm.do
#
# Description:
#   Waveform configuration for the scrubber FSM testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_scrub_fsm.do
#==============================================================================

quietly WaveActivateNextPane {} 0

#===========================================================================
# CLOCK / RESET / ENABLE
#===========================================================================
add wave -divider " PHASE / CLOCK / RESET / ENABLE"
add wave -color white  -radix unsigned sim:/tb_neorv32_scrub_fsm/test_phase
add wave -color white  -radix binary sim:/tb_neorv32_scrub_fsm/clk
add wave -color white  -radix binary sim:/tb_neorv32_scrub_fsm/rstn
add wave -color white -radix binary sim:/tb_neorv32_scrub_fsm/scrub_en

#===========================================================================
# FSM STATE
#===========================================================================
add wave -divider "FSM STATE"
add wave -color white -radix symbolic sim:/tb_neorv32_scrub_fsm/dut/current_state
add wave -color white -radix symbolic sim:/tb_neorv32_scrub_fsm/dut/next_state
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/dut/scrub_advance
add wave -color green -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/scrub_ptr

#===========================================================================
# PORT B (SCRUBBER)
#===========================================================================
add wave -divider "PORT B SCRUBBER"
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/mem_en_b
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/mem_rw_b
add wave -color orange -radix unsigned sim:/tb_neorv32_scrub_fsm/mem_addr_b
add wave -color orange -radix unsigned sim:/tb_neorv32_scrub_fsm/mem_data_b_out
add wave -color orange -radix unsigned sim:/tb_neorv32_scrub_fsm/mem_data_b_in

#===========================================================================
# PORT A (CPU)
#===========================================================================
add wave -divider "PORT A CPU"
add wave -color cyan -radix binary sim:/tb_neorv32_scrub_fsm/cpu_en
add wave -color cyan -radix binary sim:/tb_neorv32_scrub_fsm/cpu_rw
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/cpu_addr
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/cpu_data_written
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/cpu_data_read

#===========================================================================
# CPU PARITY STORE
#===========================================================================
add wave -divider "PARITY RAM STORE"
add wave -color white -radix binary   sim:/tb_neorv32_scrub_fsm/dut/ecc_stored
add wave -color orange -radix binary sim:/tb_neorv32_scrub_fsm/dut/ecc_wr_en
add wave -color orange -radix binary sim:/tb_neorv32_scrub_fsm/dut/scrub_parity
add wave -color cyan -radix binary sim:/tb_neorv32_scrub_fsm/dut/cpu_writing
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/cpu_parity
add wave -color white -radix binary   sim:/tb_neorv32_scrub_fsm/dut/scrub_par_error

#===========================================================================
# STATUS OUTPUTS
#===========================================================================
add wave -divider "STATUS"
add wave -color green -radix binary sim:/tb_neorv32_scrub_fsm/dut/conflict
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_error_det
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_error_fix
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_busy
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_full_pass
add wave -color green -radix unsigned sim:/tb_neorv32_scrub_fsm/stat_ptr


#===========================================================================
# SIMULATED MEMORY (8 words)
#===========================================================================
add wave -divider "RAM MEMORY [0:7]"
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(0)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(1)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(2)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(3)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(4)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(5)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(6)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(7)

#===========================================================================
# PARITY RAM MEMORY OF 8 WORDS
#===========================================================================
add wave -divider "ECC MEMORY [0:7]"
add wave -color white -radix binary sim:/tb_neorv32_scrub_fsm/dut/ecc_ram

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