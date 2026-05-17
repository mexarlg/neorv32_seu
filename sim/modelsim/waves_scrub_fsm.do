#------------------------------------------------------------------------------
# File: waves_scrub_fsm.do
#
# Description:
#   Waveform configuration for the scrubber FSM testbench in ModelSim.
#   Signals are grouped logically by function.
#
# Usage:
#   source waves_scrub_fsm.do
#------------------------------------------------------------------------------

quietly WaveActivateNextPane {} 0

#------------------------------------------------------------------------------
# CLOCK / RESET / ENABLE
#------------------------------------------------------------------------------
add wave -divider " PHASE / CLOCK / RESET / ENABLE"
add wave -color white  -radix unsigned sim:/tb_neorv32_scrub_fsm/test_phase
add wave -color white  -radix binary   sim:/tb_neorv32_scrub_fsm/clk
add wave -color white  -radix binary   sim:/tb_neorv32_scrub_fsm/rstn
add wave -color white  -radix binary   sim:/tb_neorv32_scrub_fsm/scrub_en

#------------------------------------------------------------------------------
# FSM STATE
#------------------------------------------------------------------------------
add wave -divider "FSM STATE"
add wave -color white -radix symbolic sim:/tb_neorv32_scrub_fsm/dut/state
add wave -color white -radix symbolic sim:/tb_neorv32_scrub_fsm/dut/state_next
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/dut/scrub_advance
add wave -color green -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/scrub_ptr

#------------------------------------------------------------------------------
# PORT B (SCRUBBER)
#------------------------------------------------------------------------------
add wave -divider "PORT B SCRUBBER"
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/scrub_en_b
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/scrub_rw_b
add wave -color orange -radix hex      sim:/tb_neorv32_scrub_fsm/scrub_addr_b
add wave -color orange -radix unsigned      sim:/tb_neorv32_scrub_fsm/scrub_data_o
add wave -color orange -radix unsigned      sim:/tb_neorv32_scrub_fsm/scrub_data_i

#------------------------------------------------------------------------------
# PORT A (CPU)
#------------------------------------------------------------------------------
add wave -divider "PORT A CPU"
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/cpu_ben
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/cpu_rw
add wave -color cyan -radix hex      sim:/tb_neorv32_scrub_fsm/cpu_addr
add wave -color cyan -radix unsigned      sim:/tb_neorv32_scrub_fsm/cpu_data_wr
add wave -color cyan -radix unsigned      sim:/tb_neorv32_scrub_fsm/cpu_data_rd

#------------------------------------------------------------------------------
# SECDED CPU ENCODER (internal)
#------------------------------------------------------------------------------
add wave -divider "SECDED CPU ENCODER"
add wave -color yellow -radix unsigned    sim:/tb_neorv32_scrub_fsm/dut/cpu_data_i
add wave -color yellow -radix hex    sim:/tb_neorv32_scrub_fsm/dut/cpu_enc_code

#------------------------------------------------------------------------------
# SECDED DECODER (internal)
#------------------------------------------------------------------------------
add wave -divider "SECDED DECODER"
add wave -color yellow -radix unsigned    sim:/tb_neorv32_scrub_fsm/dut/scrub_data_i
add wave -color yellow -radix hex    sim:/tb_neorv32_scrub_fsm/dut/ecc_stored_code
add wave -color yellow -radix unsigned    sim:/tb_neorv32_scrub_fsm/dut/dec_data_out
add wave -color yellow -radix binary sim:/tb_neorv32_scrub_fsm/dut/dec_corrected
add wave -color yellow -radix binary sim:/tb_neorv32_scrub_fsm/dut/dec_detected
add wave -color yellow -radix binary sim:/tb_neorv32_scrub_fsm/dut/dec_no_error

#------------------------------------------------------------------------------
# SECDED SCRUB ENCODER (internal)
#------------------------------------------------------------------------------
add wave -divider "SECDED SCRUB ENCODER"
add wave -color yellow -radix unsigned    sim:/tb_neorv32_scrub_fsm/dut/dec_data_out
add wave -color yellow -radix hex    sim:/tb_neorv32_scrub_fsm/dut/scrub_enc_code

#------------------------------------------------------------------------------
# ECC CODE STORE
#------------------------------------------------------------------------------
add wave -divider "ECC CODE STORE"
add wave -color white  -radix hex   sim:/tb_neorv32_scrub_fsm/dut/ecc_stored_code
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/dut/ecc_scrub_wr
add wave -color orange -radix hex   sim:/tb_neorv32_scrub_fsm/dut/scrub_enc_code
add wave -color cyan   -radix binary   sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_active
add wave -color cyan   -radix hex   sim:/tb_neorv32_scrub_fsm/dut/cpu_enc_code

#------------------------------------------------------------------------------
# FAULT LOG
#------------------------------------------------------------------------------
add wave -divider "FAULT LOG"
add wave -color red -radix binary   sim:/tb_neorv32_scrub_fsm/dut/flog_wr_en
add wave -color red -radix hex      sim:/tb_neorv32_scrub_fsm/flog_last_addr
add wave -color red -radix unsigned sim:/tb_neorv32_scrub_fsm/flog_count
add wave -color red -radix binary   sim:/tb_neorv32_scrub_fsm/flog_overflow
add wave -color red -radix binary   sim:/tb_neorv32_scrub_fsm/flog_clear

#------------------------------------------------------------------------------
# STATUS OUTPUTS
#------------------------------------------------------------------------------
add wave -divider "STATUS"
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/dut/conflict
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_data_valid
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_corrected
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_detected
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_full_pass

#------------------------------------------------------------------------------
# SIMULATED MEMORY (8 words)
#------------------------------------------------------------------------------
add wave -divider "RAM MEMORY [0:7]"
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(0)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(1)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(2)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(3)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(4)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(5)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(6)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(7)

#------------------------------------------------------------------------------
# ECC CODE STORE (8 entries)
#------------------------------------------------------------------------------
add wave -divider "ECC STORE [0:7]"
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(0)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(1)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(2)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(3)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(4)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(5)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(6)
add wave -color white -radix hex sim:/tb_neorv32_scrub_fsm/dut/ecc_store(7)


#------------------------------------------------------------------------------
# GENERAL WAVEFORM VIEWER SETTINGS
#------------------------------------------------------------------------------
configure wave -namecolwidth 280
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1
configure wave -timelineunits ns
WaveRestoreZoom {0 ns} {1000 ns}

#------------------------------------------------------------------------------
# END OF FILE
#------------------------------------------------------------------------------