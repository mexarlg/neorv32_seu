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
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/dut/scrub_ptr_incr
add wave -color green -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/scrub_ptr

#------------------------------------------------------------------------------
# PORT B (SCRUBBER)
#------------------------------------------------------------------------------
add wave -divider "PORT B SCRUBBER"
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/scrub_en_b
add wave -color orange -radix binary   sim:/tb_neorv32_scrub_fsm/scrub_rw_b
add wave -color orange -radix hex      sim:/tb_neorv32_scrub_fsm/scrub_addr_b
add wave -color orange -radix unsigned sim:/tb_neorv32_scrub_fsm/scrub_data_o
add wave -color orange -radix unsigned sim:/tb_neorv32_scrub_fsm/scrub_data_i

#------------------------------------------------------------------------------
# PORT A (CPU)
#------------------------------------------------------------------------------
add wave -divider "PORT A CPU"
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/cpu_ben
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/cpu_rw
add wave -color cyan -radix hex      sim:/tb_neorv32_scrub_fsm/cpu_addr
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/cpu_data_wr
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/cpu_data_rd

#------------------------------------------------------------------------------
# CPU WRITE PIPELINE (internal)
#------------------------------------------------------------------------------
add wave -divider "CPU WRITE PIPELINE"
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_active
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_active_q
add wave -color cyan -radix binary   sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_active_qq
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_word_q
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_word_qq
add wave -color cyan -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/cpu_data_i_q

#------------------------------------------------------------------------------
# SECDED CPU ENCODER (internal)
#------------------------------------------------------------------------------
add wave -divider "SECDED CPU ENCODER"
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/cpu_data_i_q
add wave -color yellow -radix hex      sim:/tb_neorv32_scrub_fsm/dut/cpu_enc_code
add wave -color yellow -radix hex      sim:/tb_neorv32_scrub_fsm/dut/cpu_enc_code_q

#------------------------------------------------------------------------------
# CONFLICT / ABORT
#------------------------------------------------------------------------------
add wave -divider "CONFLICT / ABORT"
add wave -color green -radix binary sim:/tb_neorv32_scrub_fsm/dut/conflict
add wave -color green -radix binary sim:/tb_neorv32_scrub_fsm/dut/abort_writeback
add wave -color green -radix binary sim:/tb_neorv32_scrub_fsm/dut/abort_clear

#------------------------------------------------------------------------------
# SCRUBBER REGISTERED READ (S_REG_READ capture)
#------------------------------------------------------------------------------
add wave -divider "SCRUBBER READ REGS"
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/scrub_data_i
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/scrub_data_i_reg
add wave -color yellow -radix hex      sim:/tb_neorv32_scrub_fsm/dut/scrub_code_i_reg

#------------------------------------------------------------------------------
# SECDED DECODER (internal)
#------------------------------------------------------------------------------
add wave -divider "SECDED DECODER"
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/scrub_data_i_reg
add wave -color yellow -radix hex      sim:/tb_neorv32_scrub_fsm/dut/scrub_code_i_reg
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/dec_data_o
add wave -color yellow -radix binary   sim:/tb_neorv32_scrub_fsm/dut/dec_corrected_o
add wave -color yellow -radix binary   sim:/tb_neorv32_scrub_fsm/dut/dec_detected_o
add wave -color yellow -radix binary   sim:/tb_neorv32_scrub_fsm/dut/dec_no_error_o

#------------------------------------------------------------------------------
# SECDED DECODER REGISTERED OUTPUTS (S_DECODE capture)
#------------------------------------------------------------------------------
add wave -divider "SECDED DECODER REGS"
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/dec_data_o_reg
add wave -color yellow -radix binary   sim:/tb_neorv32_scrub_fsm/dut/dec_corrected_o_reg
add wave -color yellow -radix binary   sim:/tb_neorv32_scrub_fsm/dut/dec_detected_o_reg
add wave -color yellow -radix binary   sim:/tb_neorv32_scrub_fsm/dut/dec_no_error_o_reg

#------------------------------------------------------------------------------
# SECDED SCRUB ENCODER (internal)
#------------------------------------------------------------------------------
add wave -divider "SECDED SCRUB ENCODER"
add wave -color yellow -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/dec_data_o_reg
add wave -color yellow -radix hex      sim:/tb_neorv32_scrub_fsm/dut/enc_code_o

#------------------------------------------------------------------------------
# SCRUBBER WRITE BACK REGS (S_REG_ENCODE capture)
#------------------------------------------------------------------------------
add wave -divider "SCRUBBER WRITE BACK REGS"
add wave -color orange -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/write_data_o
add wave -color orange -radix hex      sim:/tb_neorv32_scrub_fsm/dut/write_code_o

#------------------------------------------------------------------------------
# ECC CODE STORE (SECDED RAM)
#------------------------------------------------------------------------------
add wave -divider "ECC CODE STORE"
add wave -color white  -radix hex    sim:/tb_neorv32_scrub_fsm/dut/ecc_rdata_a
add wave -color white  -radix hex    sim:/tb_neorv32_scrub_fsm/dut/ecc_rdata_b
add wave -color orange -radix binary sim:/tb_neorv32_scrub_fsm/dut/ecc_scrub_wr_rd
add wave -color orange -radix hex    sim:/tb_neorv32_scrub_fsm/dut/write_code_o
add wave -color cyan   -radix binary sim:/tb_neorv32_scrub_fsm/dut/cpu_wr_active_qq
add wave -color cyan   -radix hex    sim:/tb_neorv32_scrub_fsm/dut/cpu_enc_code_q

#------------------------------------------------------------------------------
# STATUS OUTPUTS
#------------------------------------------------------------------------------
add wave -divider "STATUS"
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_data_valid
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_corrected
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_detected
add wave -color green -radix binary   sim:/tb_neorv32_scrub_fsm/stat_full_pass

#------------------------------------------------------------------------------
# SIMULATED DATA MEMORY (8 words)
#------------------------------------------------------------------------------
add wave -divider "DATA RAM [0:7]"
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(0)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(1)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(2)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(3)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(4)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(5)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(6)
add wave -color white -radix unsigned sim:/tb_neorv32_scrub_fsm/fake_mem(7)

#------------------------------------------------------------------------------
# SIMULATED SECDED MEMORY (8 words)
#------------------------------------------------------------------------------
add wave -divider "SECDED RAM [0:7]"
add wave -color green -radix unsigned sim:/tb_neorv32_scrub_fsm/dut/ecc_mem



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