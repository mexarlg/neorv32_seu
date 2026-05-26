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
-- Pipeline (one word nominal scrub cycle):                                         --
--   S_ISSUE_READ  : issue BRAM read (DMEM + ECC RAM)                               --
--   S_REG_READ    : BRAM outputs settle, capture into read registers               --
--   S_DECODE      : decoder runs on registered inputs, status flags captured       --
--   S_CHECK       : act on registered status flags                                 --
--   S_REG_ENCODE  : encoder runs on registered corrected data, write data captured --
--   S_ISSUE_WRITE : issue BRAM write back from registers (flop to flop path)       --
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
        DMEM_DEPTH  : natural; -- number of 32 bit words (DMEM_SIZE / 4)
        SCRUB_START : natural; -- first word index to scrub
        SCRUB_END   : natural  -- last word index to scrub
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
    -- Constants
    -- -------------------------------------------------------------------------
    constant C_WORD_ADDR_MSB : natural := DMEM_AWIDTH - 1;
    constant C_WORD_ADDR_LSB : natural := 2;

    -- -------------------------------------------------------------------------
    -- FSM STATES (NOMINAL, NO CONFLICT)
    --
    -- 1) S_ISSUE_READ: Issues read on data BRAM and secded BRAM
    -- 2) S_REG_READ: Registers data and secded code from BRAM outputs
    -- 3) S_DECODE: Decoder decodes secded and fixes data from reg inputs, combinational outputs are registered
    -- 4) S_CHECK: Decoder outputs are already registered, checks error type and issues encoder
    -- 5) S_REG_ENCODE: Registers encoder output (secded code)
    -- 6) S_ISSUE_WRITE: Issues write transaction into data BRAM and secded BRAM on port B
    --
    -- -------------------------------------------------------------------------
    type scrub_state_t is (S_IDLE, S_ISSUE_READ, S_REG_READ, S_DECODE, S_CHECK, S_REG_ENCODE, S_ISSUE_WRITE);
    signal state      : scrub_state_t;
    signal state_next : scrub_state_t;

    -- -------------------------------------------------------------------------
    -- CPU WRITE PATH: TWO STAGE PIPELINE
    -- Stage 1 (_q):  captures cpu write inputs and issues cpu encoder to compute secded
    -- Stage 2 (_qq): registers encoder outputs and updates secded BRAM
    -- -------------------------------------------------------------------------

    -- Indicates a cpu write enable on data BRAM port A (comb, _q are reg)
    signal cpu_wr_active    : std_ulogic;
    signal cpu_wr_active_q  : std_ulogic;
    signal cpu_wr_active_qq : std_ulogic;
    -- Cpu word address to write (reg)
    signal cpu_wr_word_q  : unsigned(C_WORD_ADDR_MSB - C_WORD_ADDR_LSB downto 0);
    signal cpu_wr_word_qq : unsigned(C_WORD_ADDR_MSB - C_WORD_ADDR_LSB downto 0);
    -- Cpu data to be written (reg)
    signal cpu_data_i_q : std_ulogic_vector(31 downto 0);
    -- Encoded secded code from data of cpu write (comb, reg)
    signal cpu_enc_code   : std_ulogic_vector(6 downto 0);
    signal cpu_enc_code_q : std_ulogic_vector(6 downto 0);

    -- -------------------------------------------------------------------------
    -- SCRUBBER POINTER AND ADDRESS
    -- -------------------------------------------------------------------------
    signal scrub_ptr       : unsigned(C_WORD_ADDR_MSB - C_WORD_ADDR_LSB downto 0);
    signal scrub_ptr_incr  : std_ulogic;
    signal scrub_byte_addr : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- SECDED RAM signals (8 bit for BRAM, SECDED uses lower 7 bits)
    -- -------------------------------------------------------------------------
    signal ecc_rdata_a     : std_ulogic_vector(7 downto 0); -- Port A read
    signal ecc_rdata_b     : std_ulogic_vector(7 downto 0); -- Port B read
    signal ecc_scrub_wr_rd : std_ulogic;                    -- Write / read enable

    -- -------------------------------------------------------------------------
    -- SCRUBBER REGISTERED READ SECDED AND DATA FROM S_ISSUE_READ TO S_REG_READ
    -- -------------------------------------------------------------------------
    signal scrub_data_i_reg : std_ulogic_vector(31 downto 0);
    signal scrub_code_i_reg : std_ulogic_vector(6 downto 0);

    -- -------------------------------------------------------------------------
    -- SCRUBBER DECODER COMBINATIONAL OUTPUTS
    -- -------------------------------------------------------------------------
    signal dec_data_o      : std_ulogic_vector(31 downto 0);
    signal dec_corrected_o : std_ulogic;
    signal dec_detected_o  : std_ulogic;
    signal dec_no_error_o  : std_ulogic;

    -- -------------------------------------------------------------------------
    -- SCRUBBER DECODER REGISTERED OUTPUTS FROM S_DECODE TO S_CHECK
    -- -------------------------------------------------------------------------
    signal dec_data_o_reg      : std_ulogic_vector(31 downto 0);
    signal dec_corrected_o_reg : std_ulogic;
    signal dec_detected_o_reg  : std_ulogic;
    signal dec_no_error_o_reg  : std_ulogic;

    -- -------------------------------------------------------------------------
    -- SCRUBBER ENCODER COMBINATIONAL
    -- -------------------------------------------------------------------------
    signal enc_code_o : std_ulogic_vector(6 downto 0);

    -- -------------------------------------------------------------------------
    -- SCRUBBER WRITE BACK REGISTERED OUTPUTS FROM S_REG_ENCODER TO S_ISSUE_WRITE
    -- -------------------------------------------------------------------------
    signal write_data_o : std_ulogic_vector(31 downto 0);
    signal write_code_o : std_ulogic_vector(6 downto 0);

    -- -------------------------------------------------------------------------
    -- CONFLICT DETECTION
    --   conflict        : 1 when reading same addresss as cpu write (early states)
    --   abort_writeback : 1 if a conflict is detected after word has been read (latter states)
    -- -------------------------------------------------------------------------
    signal conflict        : std_ulogic;
    signal abort_writeback : std_ulogic;
    signal abort_clear     : std_ulogic;

    -- -------------------------------------------------------------------------
    -- FAULT LOG OF DETECTED (UNFIXABLE) ERRORS
    -- -------------------------------------------------------------------------
    signal flog_wr_en     : std_ulogic;
    signal flog_last_addr : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal flog_count     : unsigned(7 downto 0);
    signal flog_overflow  : std_ulogic;

    -- -------------------------------------------------------------------------
    -- SIMULATED SECDED BRAM ARRAY (UNCOMMENT IF SIMULATION)
    -- -------------------------------------------------------------------------
    --type ecc_mem_t is array (0 to DMEM_DEPTH - 1) of std_ulogic_vector(7 downto 0);
    --signal ecc_mem : ecc_mem_t := (others => (others => '0'));

begin

    ----------------------------------------------------------------------------
    -- SECDED ENCODER / DECODER
    ----------------------------------------------------------------------------

    -- CPU encoder: computes secded from registered CPU write data
    u_cpu_encoder : entity neorv32.neorv32_secded_encoder
        port map(
            data_i   => cpu_data_i_q,
            secded_o => cpu_enc_code
        );

    -- Scrubber decoder: checks registered read data from scrubber against stored secded (comb outputs)
    u_scrub_decoder : entity neorv32.neorv32_secded_decoder
        port map(
            data_i            => scrub_data_i_reg,
            check_i           => scrub_code_i_reg,
            data_o            => dec_data_o,
            stat_corrected_o  => dec_corrected_o,
            stat_detected_o   => dec_detected_o,
            stat_data_valid_o => dec_no_error_o
        );

    -- Scrubber encoder: recomputes secded from registered corrected data
    u_scrub_encoder : entity neorv32.neorv32_secded_encoder
        port map(
            data_i   => dec_data_o_reg,
            secded_o => enc_code_o
        );

    -- -------------------------------------------------------------------------
    -- CPU WRITE PATH: TWO STAGE PIPELINE
    -- -------------------------------------------------------------------------

    cpu_wr_active <= '1' when (cpu_ben_i /= "0000") and (cpu_rw_i = '1') else
        '0';

    p_cpu_reg : process (clk_i)
    begin
        if rising_edge(clk_i) then
            -- Stage 1: capture bus inputs
            cpu_wr_active_q <= cpu_wr_active;
            cpu_wr_word_q   <= unsigned(cpu_addr_i(C_WORD_ADDR_MSB downto C_WORD_ADDR_LSB));
            cpu_data_i_q    <= cpu_data_i;
            -- Stage 2: capture encoder output
            cpu_enc_code_q   <= cpu_enc_code;
            cpu_wr_active_qq <= cpu_wr_active_q;
            cpu_wr_word_qq   <= cpu_wr_word_q;
        end if;
    end process p_cpu_reg;

    -- -------------------------------------------------------------------------
    -- CONFLICT DETECTION
    -- -------------------------------------------------------------------------

    conflict <= '1' when
        ((cpu_wr_active_q = '1') and (cpu_wr_word_q = scrub_ptr)) or
        ((cpu_wr_active_qq = '1') and (cpu_wr_word_qq = scrub_ptr))
        else
        '0';

    p_abort : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            abort_writeback <= '0';
        elsif rising_edge(clk_i) then
            if (conflict = '1') and (state /= S_IDLE) then
                abort_writeback <= '1';
            elsif (abort_clear = '1') then
                abort_writeback <= '0';
            end if;
        end if;
    end process p_abort;

    -- -------------------------------------------------------------------------
    -- SCRUBBER REGISTERED READ SECDED AND DATA FROM S_ISSUE_READ TO S_REG_READ
    -- -------------------------------------------------------------------------

    p_read_reg : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if (state = S_REG_READ) then
                scrub_data_i_reg <= scrub_data_i;
                scrub_code_i_reg <= ecc_rdata_b(6 downto 0);
            end if;
        end if;
    end process p_read_reg;

    -- -------------------------------------------------------------------------
    -- SCRUBBER DECODER REGISTERED OUTPUTS FROM S_DECODE TO S_CHECK
    -- -------------------------------------------------------------------------

    p_dec_reg : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            dec_data_o_reg      <= (others => '0');
            dec_corrected_o_reg <= '0';
            dec_detected_o_reg  <= '0';
            dec_no_error_o_reg  <= '0';
        elsif rising_edge(clk_i) then
            if (state = S_DECODE) then
                dec_data_o_reg      <= dec_data_o;
                dec_corrected_o_reg <= dec_corrected_o;
                dec_detected_o_reg  <= dec_detected_o;
                dec_no_error_o_reg  <= dec_no_error_o;
            end if;
        end if;
    end process p_dec_reg;

    -- -------------------------------------------------------------------------
    -- SCRUBBER WRITE BACK REGISTERED OUTPUTS FROM S_REG_ENCODER TO S_ISSUE_WRITE
    -- -------------------------------------------------------------------------

    p_write_reg : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if (state = S_REG_ENCODE) then
                write_data_o <= dec_data_o_reg;
                write_code_o <= enc_code_o;
            end if;
        end if;
    end process p_write_reg;

    ----------------------------------------------------------------------------
    -- SCRUBBER ADDRESS AND OUTPUTS
    ----------------------------------------------------------------------------

    scrub_byte_addr <= std_ulogic_vector(scrub_ptr) & "00";
    scrub_addr_o    <= scrub_byte_addr;
    stat_addr_o     <= scrub_byte_addr;

    scrub_data_o <= write_data_o;

    -- -------------------------------------------------------------------------
    -- SECDED 8 BIT BRAM
    --  Port A: CPU write (two stage pipeline)
    --  Port B: Scrubber read (always) and write (on correction)
    -- -------------------------------------------------------------------------

    -- REAL AND TO BE IMPLEMENTED SECDED BRAM
    u_ecc_ram : entity neorv32.neorv32_prim_dpram
        generic map(
            AWIDTH => DMEM_AWIDTH - 2,
            DWIDTH => 8,
            OUTREG => false
        )
        port map(
            clk_i => clk_i,
            -- Port A: CPU write
            en_a_i   => cpu_wr_active_qq,
            rw_a_i   => '1',
            addr_a_i => std_ulogic_vector(cpu_wr_word_qq),
            data_a_i => '0' & cpu_enc_code_q,
            data_a_o => ecc_rdata_a,
            -- Port B: Scrubber read/write
            en_b_i   => '1',
            rw_b_i   => ecc_scrub_wr_rd,
            addr_b_i => std_ulogic_vector(scrub_ptr),
            data_b_i => '0' & write_code_o,
            data_b_o => ecc_rdata_b
        );

    -- UNCOMMENT FOR SIMULATION SECDED RAM
    --p_ecc_ram : process (clk_i)
    --begin
    --    if rising_edge(clk_i) then
    --
    --        -- Port A: CPU write (write only, gated by enable)
    --        if (cpu_wr_active_qq = '1') then
    --            ecc_mem(to_integer(cpu_wr_word_qq)) <= '0' & cpu_enc_code_q;
    --            ecc_rdata_a                         <= ecc_mem(to_integer(cpu_wr_word_qq));
    --        end if;
    --
    --        -- Port B: Scrubber (always enabled, rw selects)
    --        if (ecc_scrub_wr_rd = '1') then
    --            ecc_mem(to_integer(scrub_ptr)) <= '0' & write_code_o;
    --        end if;
    --        ecc_rdata_b <= ecc_mem(to_integer(scrub_ptr));
    --
    --    end if;
    --end process p_ecc_ram;

    -- -------------------------------------------------------------------------
    -- FSM SEQUENTIAL
    -- -------------------------------------------------------------------------

    p_seq : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            state     <= S_IDLE;
            scrub_ptr <= to_unsigned(SCRUB_START, scrub_ptr'length);

        elsif rising_edge(clk_i) then
            state <= state_next;

            if (scrub_ptr_incr = '1') then
                if (scrub_ptr = SCRUB_END) then
                    scrub_ptr <= to_unsigned(SCRUB_START, scrub_ptr'length);
                else
                    scrub_ptr <= scrub_ptr + 1;
                end if;
            end if;

        end if;
    end process p_seq;

    -- -------------------------------------------------------------------------
    -- FSM COMBINATIONAL
    --
    -- 1) S_ISSUE_READ: Issues read on data BRAM and secded BRAM
    -- 2) S_REG_READ: Registers data and secded code from BRAM outputs
    -- 3) S_DECODE: Decoder decodes secded and fixes data from reg inputs, combinational outputs are registered
    -- 4) S_CHECK: Decoder outputs are already registered, checks error type and issues encoder
    -- 5) S_REG_ENCODE: Registers encoder output (secded code)
    -- 6) S_ISSUE_WRITE: Issues write transaction into data BRAM and secded BRAM on port B
    --
    -- -------------------------------------------------------------------------

    p_comb : process (state, conflict, abort_writeback, scrub_en_i,
        dec_corrected_o_reg, dec_detected_o_reg, dec_no_error_o_reg)
    begin
        state_next        <= state;
        scrub_en_o        <= '0';
        scrub_rw_o        <= '0';
        stat_data_valid_o <= '0';
        stat_corrected_o  <= '0';
        stat_detected_o   <= '0';
        ecc_scrub_wr_rd   <= '0';
        scrub_ptr_incr    <= '0';
        flog_wr_en        <= '0';
        abort_clear       <= '0';

        case state is

            when S_IDLE =>
                abort_clear <= '1';
                if (scrub_en_i = '1') then
                    state_next <= S_ISSUE_READ;
                end if;

            when S_ISSUE_READ =>
                -- issue BRAM read if no conflict, stall otherwise
                if (scrub_en_i = '0') then
                    state_next <= S_IDLE;
                elsif (conflict = '0') then
                    scrub_en_o <= '1';
                    state_next <= S_REG_READ;
                end if;

            when S_REG_READ =>
                -- BRAM outputs are captured into scrub_data_i_reg / scrub_code_i_reg
                if (conflict = '1') then
                    state_next <= S_ISSUE_READ;
                else
                    state_next <= S_DECODE;
                end if;

            when S_DECODE =>
                -- Decoder runs on reg inputs and outputs are reg at end of state
                if (conflict = '1') then
                    state_next <= S_ISSUE_READ;
                else
                    state_next <= S_CHECK;
                end if;

            when S_CHECK =>
                -- Registered decoder flags are stable and Encoder is started
                if (abort_writeback = '1') or (conflict = '1') then
                    -- Conflict, go to start
                    abort_clear <= '1';
                    state_next  <= S_ISSUE_READ;

                elsif (dec_no_error_o_reg = '1') then
                    -- Data correct, next word
                    stat_data_valid_o <= '1';
                    scrub_ptr_incr    <= '1';
                    abort_clear       <= '1';
                    state_next        <= S_ISSUE_READ;

                elsif (dec_corrected_o_reg = '1') then
                    -- Data is fixed, write on memory
                    stat_corrected_o <= '1';
                    state_next       <= S_REG_ENCODE;

                elsif (dec_detected_o_reg = '1') then
                    -- Data is not fixable, log it and go to next word
                    stat_detected_o <= '1';
                    flog_wr_en      <= '1';
                    scrub_ptr_incr  <= '1';
                    abort_clear     <= '1';
                    state_next      <= S_ISSUE_READ;

                end if;

            when S_REG_ENCODE =>
                -- Encoder runs on dec_data_o_reg this cycle, write_data_o and write_code_o are output
                if (abort_writeback = '1') or (conflict = '1') then
                    abort_clear <= '1';
                    state_next  <= S_ISSUE_READ;
                else
                    state_next <= S_ISSUE_WRITE;
                end if;

            when S_ISSUE_WRITE =>
                -- issue write back of data and secded into BRAMs
                if (abort_writeback = '1') or (conflict = '1') then
                    abort_clear <= '1';
                    state_next  <= S_ISSUE_READ;
                else
                    scrub_en_o      <= '1';
                    scrub_rw_o      <= '1';
                    ecc_scrub_wr_rd <= '1';
                    scrub_ptr_incr  <= '1';
                    abort_clear     <= '1';
                    state_next      <= S_ISSUE_READ;
                end if;

            when others =>
                state_next <= S_IDLE;

        end case;
    end process p_comb;

    -- -------------------------------------------------------------------------
    -- FAULT LOG OF DETECTED (UNFIXABLE) ERRORS
    -- -------------------------------------------------------------------------

    p_fault_log : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            flog_last_addr <= (others => '0');
            flog_count     <= (others => '0');
            flog_overflow  <= '0';

        elsif rising_edge(clk_i) then
            if (flog_clear_i = '1') then
                flog_last_addr <= (others => '0');
                flog_count     <= (others => '0');
                flog_overflow  <= '0';

            elsif (flog_wr_en = '1') then
                flog_last_addr <= scrub_byte_addr;
                if (flog_count = 255) then
                    flog_overflow <= '1';
                else
                    flog_count <= flog_count + 1;
                end if;

            end if;
        end if;
    end process p_fault_log;

    flog_last_addr_o <= flog_last_addr;
    flog_count_o     <= std_ulogic_vector(flog_count);
    flog_overflow_o  <= flog_overflow;

    -- -------------------------------------------------------------------------
    -- STATUS OUTPUTS
    -- -------------------------------------------------------------------------

    stat_state_o <= "000" when state = S_IDLE else
        "001" when state = S_ISSUE_READ else
        "010" when state = S_REG_READ else
        "011" when state = S_DECODE else
        "100" when state = S_CHECK else
        "101" when state = S_REG_ENCODE else
        "110" when state = S_ISSUE_WRITE else
        "111";

    stat_conflict_o <= conflict;

    stat_busy_o <= '0' when state = S_IDLE else
        '1';

    stat_full_pass_o <= '1' when (scrub_ptr_incr = '1') and
        (scrub_ptr = SCRUB_END) else
        '0';

end neorv32_scrub_fsm_rtl;