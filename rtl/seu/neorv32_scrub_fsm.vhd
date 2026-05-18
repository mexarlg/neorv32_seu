-- -------------------------------------------------------------------------------- --
-- NEORV32 SoC - DMEM Background Scrubber FSM                                       --
-- -------------------------------------------------------------------------------- --
-- Continuously iterates over all words in DMEM via Port B of a dual port RAM.      --
-- Reads each word, checks SECDED code against the ECC store, and writes back       --
-- corrected data on a single bit mismatch. Flags double bit errors.                --
-- Runs entirely in the background without stalling the CPU.                        --
--                                                                                  --
-- The encoder and decoder are instantiated internally. The CPU path uses a         --
-- dedicated encoder instance so there is no resource sharing conflict between      --
-- CPU writes and scrubber write backs.                                             --
--                                                                                  --
--      Author: Aldo Lupio - 2026                                                   --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- -------------------------------------------------------------------------------- --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;

entity neorv32_scrub_fsm is
    generic (
        DMEM_AWIDTH : natural; -- byte address width of DMEM
        DMEM_DEPTH  : natural  -- number of 32 bit words (DMEM_SIZE / 4)
    );
    port (
        -- Global control
        clk_i      : in std_ulogic; -- clock
        rstn_i     : in std_ulogic; -- async reset_n
        scrub_en_i : in std_ulogic; -- enables scrubber passes

        -- CPU write monitoring (directly from DMEM port A signals)
        cpu_ben_i  : in std_ulogic_vector(3 downto 0);               -- transaction enable (4 ram instantiations)
        cpu_rw_i   : in std_ulogic;                                  -- write / read operation
        cpu_addr_i : in std_ulogic_vector(DMEM_AWIDTH - 1 downto 0); -- byte address
        cpu_data_i : in std_ulogic_vector(31 downto 0);              -- 32 bit data word

        -- Scrubber port B interface
        scrub_en_o   : out std_ulogic;                                  -- transaction enable
        scrub_rw_o   : out std_ulogic;                                  -- write / read operation
        scrub_addr_o : out std_ulogic_vector(DMEM_AWIDTH - 1 downto 0); -- byte address
        scrub_data_o : out std_ulogic_vector(31 downto 0);              -- 32 bit data word written
        scrub_data_i : in std_ulogic_vector(31 downto 0);               -- 32 bit data word read

        -- Fault log of unfixable errors addresses (corrupted addr)
        flog_clear_i     : in std_ulogic;
        flog_last_addr_o : out std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
        flog_count_o     : out std_ulogic_vector(7 downto 0);
        flog_overflow_o  : out std_ulogic;

        -- Status outputs
        stat_data_valid_o : out std_ulogic;                                  -- data checked is found valid
        stat_corrected_o  : out std_ulogic;                                  -- 1 bit error corrected by decoder, data valid after correction
        stat_detected_o   : out std_ulogic;                                  -- 2 bit error detected by decoder, data not valid
        stat_state_o      : out std_ulogic_vector(2 downto 0);               -- state encoded
        stat_addr_o       : out std_ulogic_vector(DMEM_AWIDTH - 1 downto 0); -- current address pointer
        stat_conflict_o   : out std_ulogic;                                  -- cpu writing on same address as current scrubber address
        stat_busy_o       : out std_ulogic;                                  -- scrubber active (not in idle state)
        stat_full_pass_o  : out std_ulogic                                   -- full revolution done on memory
    );
end neorv32_scrub_fsm;

architecture neorv32_scrub_fsm_rtl of neorv32_scrub_fsm is

    -- -------------------------------------------------------------------------
    -- Components declaration
    -- -------------------------------------------------------------------------
    --component neorv32_secded_encoder
    --    port (
    --        data_i   : in std_ulogic_vector(31 downto 0);
    --        secded_o : out std_ulogic_vector(6 downto 0)
    --    );
    --end component;

    --component neorv32_secded_decoder
    --    port (
    --        data_i            : in std_ulogic_vector(31 downto 0);
    --        check_i           : in std_ulogic_vector(6 downto 0);
    --        data_o            : out std_ulogic_vector(31 downto 0);
    --        stat_corrected_o  : out std_ulogic;
    --        stat_detected_o   : out std_ulogic;
    --        stat_data_valid_o : out std_ulogic
    --    );
    --end component;

    -- -------------------------------------------------------------------------
    -- Constants
    -- -------------------------------------------------------------------------
    constant WORD_ADDR_MSB : natural := DMEM_AWIDTH - 1;
    constant WORD_ADDR_LSB : natural := 2;

    -- -------------------------------------------------------------------------
    -- FSM
    -- -------------------------------------------------------------------------
    type scrub_state_t is (S_IDLE, S_READ, S_CHECK, S_WRITE);
    signal state      : scrub_state_t;
    signal state_next : scrub_state_t;

    -- -------------------------------------------------------------------------
    -- Scrubber pointer (word index)
    -- -------------------------------------------------------------------------
    signal scrub_ptr       : unsigned(WORD_ADDR_MSB - WORD_ADDR_LSB downto 0);
    signal scrub_advance   : std_ulogic;
    signal scrub_byte_addr : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- ECC code store
    -- -------------------------------------------------------------------------
    type ecc_store_t is array (0 to DMEM_DEPTH - 1) of std_ulogic_vector(7 downto 0);
    signal ecc_store       : ecc_store_t := (others => (others => '0'));
    signal ecc_stored_code : std_ulogic_vector(6 downto 0);
    signal ecc_scrub_wr    : std_ulogic;
    signal ecc_rdata_a     : std_ulogic_vector(7 downto 0);

    -- -------------------------------------------------------------------------
    -- CPU write path
    -- -------------------------------------------------------------------------
    signal cpu_wr_active : std_ulogic;
    signal cpu_wr_word   : unsigned(WORD_ADDR_MSB - WORD_ADDR_LSB downto 0);
    signal cpu_enc_code  : std_ulogic_vector(6 downto 0);

    -- -------------------------------------------------------------------------
    -- Scrubber decoder and encoder wiring
    -- -------------------------------------------------------------------------
    signal dec_data_out   : std_ulogic_vector(31 downto 0);
    signal dec_corrected  : std_ulogic;
    signal dec_detected   : std_ulogic;
    signal dec_no_error   : std_ulogic;
    signal scrub_enc_code : std_ulogic_vector(6 downto 0);

    -- -------------------------------------------------------------------------
    -- Fault log: last address, count, overflow
    -- -------------------------------------------------------------------------
    signal flog_wr_en        : std_ulogic;
    signal flog_last_addr    : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal flog_count        : unsigned(7 downto 0);
    signal flog_overflow     : std_ulogic;
    signal scrub_byte_addr_q : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- Conflict detection
    -- -------------------------------------------------------------------------
    signal conflict : std_ulogic;

begin

    -- -------------------------------------------------------------------------
    -- SECDED encoder / decoder instances
    -- -------------------------------------------------------------------------

    -- CPU encoder: computes check bits for CPU write data
    u_cpu_encoder : entity neorv32.neorv32_secded_encoder
        port map(
            data_i   => cpu_data_i,
            secded_o => cpu_enc_code
        );

    -- Scrubber decoder: checks read data against stored code
    u_scrub_decoder : entity neorv32.neorv32_secded_decoder
        port map(
            data_i            => scrub_data_i,
            check_i           => ecc_stored_code,
            data_o            => dec_data_out,
            stat_corrected_o  => dec_corrected,
            stat_detected_o   => dec_detected,
            stat_data_valid_o => dec_no_error
        );

    -- Scrubber encoder: recomputes code from corrected data for write-back
    u_scrub_encoder : entity neorv32.neorv32_secded_encoder
        port map(
            data_i   => dec_data_out,
            secded_o => scrub_enc_code
        );

    -- -------------------------------------------------------------------------
    -- Address handling and static wiring
    -- -------------------------------------------------------------------------

    -- From word addr (scrub_ptr) to byte addr (external)
    scrub_byte_addr <= std_ulogic_vector(scrub_ptr) & "00";
    scrub_addr_o    <= scrub_byte_addr;
    stat_addr_o     <= scrub_byte_addr;

    -- From byte addr to word addr
    cpu_wr_word  <= unsigned(cpu_addr_i(WORD_ADDR_MSB downto WORD_ADDR_LSB));
    scrub_data_o <= dec_data_out;

    -- -------------------------------------------------------------------------
    -- ECC Secded 8 bit RAM storage (to avoid timing violations, SECDED is 7 bit)
    -- -------------------------------------------------------------------------

    -- Port A: CPU write
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if (cpu_wr_active = '1') then
                ecc_store(to_integer(cpu_wr_word)) <= '0' & cpu_enc_code;
            end if;
            ecc_rdata_a <= ecc_store(to_integer(cpu_wr_word));
        end if;
    end process;

    -- Port B: Scrubber read/write
    process (clk_i)
    begin
        if rising_edge(clk_i) then
            if (ecc_scrub_wr = '1') then
                ecc_store(to_integer(scrub_ptr)) <= '0' & scrub_enc_code;
            end if;
            ecc_stored_code <= ecc_store(to_integer(scrub_ptr))(6 downto 0);
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Conflict detection
    -- -------------------------------------------------------------------------

    cpu_wr_active <= '1' when (cpu_ben_i /= "0000") and (cpu_rw_i = '1') else
        '0';

    conflict <= '1' when (cpu_wr_active = '1') and (cpu_wr_word = scrub_ptr) else
        '0';

    -- -------------------------------------------------------------------------
    -- FSM sequential: state register and pointer
    -- -------------------------------------------------------------------------

    p_seq : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            state     <= S_IDLE;
            scrub_ptr <= (others => '0');

        elsif rising_edge(clk_i) then
            state <= state_next;

            -- increase or restart pointer
            if (scrub_advance = '1') then
                if (scrub_ptr = DMEM_DEPTH - 1) then
                    scrub_ptr <= (others => '0');
                else
                    scrub_ptr <= scrub_ptr + 1;
                end if;
            end if;

        end if;
    end process p_seq;

    -- -------------------------------------------------------------------------
    -- FSM combinational: next state and outputs
    -- -------------------------------------------------------------------------

    p_comb : process (state, conflict, scrub_en_i,
        dec_corrected, dec_detected, dec_no_error)
    begin
        -- srub next state and scrub wr/rd issue signals 
        state_next <= state;
        scrub_en_o <= '0';
        scrub_rw_o <= '0';
        -- status of data
        stat_data_valid_o <= '0';
        stat_corrected_o  <= '0';
        stat_detected_o   <= '0';
        -- issue update of secded, incr of pointer, update of fault reg
        ecc_scrub_wr  <= '0';
        scrub_advance <= '0';
        flog_wr_en    <= '0';

        case state is

            when S_IDLE =>
                -- scrubber enabled
                if (scrub_en_i = '1') then
                    state_next <= S_READ;
                end if;

            when S_READ =>
                -- change to check if there is no conflict, stall otherwise
                if (conflict = '0') then
                    scrub_en_o <= '1';
                    state_next <= S_CHECK;
                end if;

            when S_CHECK =>
                -- go back to read if there is a conflict
                if (conflict = '1') then
                    state_next <= S_READ;

                    -- no error on data, go to next word
                elsif (dec_no_error = '1') then
                    stat_data_valid_o <= '1';
                    scrub_advance     <= '1';
                    state_next        <= S_READ;

                    -- 1 bit error on data, go to S_WRITE to update it on ram
                elsif (dec_corrected = '1') then
                    stat_corrected_o <= '1';
                    state_next       <= S_WRITE;

                    -- 2 bit error on data detected, flag and go to next word
                elsif (dec_detected = '1') then
                    stat_detected_o <= '1';
                    flog_wr_en      <= '1';
                    scrub_advance   <= '1';
                    state_next      <= S_READ;

                end if;

            when S_WRITE =>
                -- stall if conflict, issue write otherwise
                if (conflict = '1') then
                    state_next <= S_READ;
                else
                    -- write issued
                    scrub_en_o   <= '1';
                    scrub_rw_o   <= '1';
                    ecc_scrub_wr <= '1';
                    -- next word
                    scrub_advance <= '1';
                    state_next    <= S_READ;
                end if;

            when others =>
                state_next <= S_IDLE;

        end case;
    end process p_comb;

    -- -------------------------------------------------------------------------
    -- Log of last corrupted address (unfixable errors)
    -- -------------------------------------------------------------------------

    -- Latch address during S_CHECK
    process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            scrub_byte_addr_q <= (others => '0');
        elsif rising_edge(clk_i) then
            scrub_byte_addr_q <= scrub_byte_addr;
        end if;
    end process;

    p_fault_log : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            flog_last_addr <= (others => '0');
            flog_count     <= (others => '0');
            flog_overflow  <= '0';

        elsif rising_edge(clk_i) then
            -- restart the log history from sw 
            if (flog_clear_i = '1') then
                flog_last_addr <= (others => '0');
                flog_count     <= (others => '0');
                flog_overflow  <= '0';

                -- update log with latest unvalid address
            elsif (flog_wr_en = '1') then
                flog_last_addr <= scrub_byte_addr_q;
                -- increase count until overflow
                if (flog_count = 255) then
                    flog_overflow <= '1';
                else
                    flog_count <= flog_count + 1;
                end if;

            end if;
        end if;
    end process p_fault_log;

    -- output signals converted
    flog_last_addr_o <= flog_last_addr;
    flog_count_o     <= std_ulogic_vector(flog_count);
    flog_overflow_o  <= flog_overflow;

    -- -------------------------------------------------------------------------
    -- Status outputs
    -- -------------------------------------------------------------------------

    stat_state_o <= "000" when state = S_IDLE else
        "001" when state = S_READ else
        "010" when state = S_CHECK else
        "011" when state = S_WRITE else
        "111";

    stat_conflict_o <= conflict;

    stat_busy_o <= '0' when state = S_IDLE else
        '1';

    stat_full_pass_o <= '1' when (scrub_advance = '1') and
        (scrub_ptr = DMEM_DEPTH - 1) else
        '0';

end neorv32_scrub_fsm_rtl;