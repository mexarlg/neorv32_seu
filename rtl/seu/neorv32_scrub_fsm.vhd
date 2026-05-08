-- ================================================================================ --
-- NEORV32 SoC - DMEM Background Scrubber FSM                                       --
-- -------------------------------------------------------------------------------- --
-- Continuously iterates over all words in DMEM via Port B of a dual-port RAM.      --
-- Reads each word, checks parity against the ECC store, and writes back corrected  --
-- data on a mismatch. Runs entirely in the background without stalling the CPU.    --
--                                                                                  --
-- Collision handling: when the CPU writes to the same address the scrubber is      --
-- acessing, the scrubber stalls. The CPU is never affected.                        --
--                                                                                  --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_scrub_fsm is
    generic (
        AWIDTH    : natural; -- byte address width (same as DMEM)
        MEM_DEPTH : natural  -- number of 32-bit words (= DMEM_SIZE / 4)
    );
    port (
        -- Global control
        clk_i       : in std_ulogic; -- clock, rising edge
        rstn_i      : in std_ulogic; -- async reset, low-active
        scrubber_en : in std_ulogic; -- scrubber enable

        -- Port A (CPU)
        cpu_en_i   : in std_ulogic_vector(3 downto 0);  -- CPU byte enables
        cpu_rw_i   : in std_ulogic;                     -- CPU 0=read 1=write
        cpu_addr_i : in std_ulogic_vector(31 downto 0); -- CPU byte address
        cpu_data_i : in std_ulogic_vector(31 downto 0); -- CPU write data

        -- Port B (Scrubber)
        mem_en_b_o   : out std_ulogic;                             -- Port B access enable
        mem_rw_b_o   : out std_ulogic;                             -- Port B 0=read 1=write
        mem_addr_b_o : out std_ulogic_vector(AWIDTH - 3 downto 0); -- Port B word address
        mem_data_b_o : out std_ulogic_vector(31 downto 0);         -- Port B write data
        mem_data_b_i : in std_ulogic_vector(31 downto 0);          -- Port B read data

        -- Status
        stat_error_det_o : out std_ulogic;                    -- parity mismatch detected (pulse)
        stat_error_fix_o : out std_ulogic;                    -- parity fixed on ecc ram (pulse)
        stat_state_o     : out std_ulogic_vector(2 downto 0); -- FSM state encoded
        stat_ptr_o       : out std_ulogic_vector(AWIDTH - 3 downto 0);-- current scrub address
        stat_conflict_o  : out std_ulogic; -- CPU/scrubber address conflict
        stat_busy_o      : out std_ulogic; -- scrubber active
        stat_full_pass_o : out std_ulogic  -- full memory pass completed
    );
end neorv32_scrub_fsm;

architecture neorv32_scrub_fsm_rtl of neorv32_scrub_fsm is

    -- -------------------------------------------------------------------------
    -- Parity function - even parity, shared by CPU path and scrubber path
    -- -------------------------------------------------------------------------
    function compute_parity(data : std_ulogic_vector(31 downto 0))
        return std_ulogic is
        variable p : std_ulogic;
    begin
        p := '0';
        for i in 0 to 31 loop
            p := p xor data(i);
        end loop;
        return p;
    end function;

    -- -------------------------------------------------------------------------
    -- FSM
    -- -------------------------------------------------------------------------
    type scrub_state_t is (S_IDLE, S_READ, S_CHECK, S_WRITE);
    signal current_state : scrub_state_t;
    signal next_state    : scrub_state_t;

    -- -------------------------------------------------------------------------
    -- Scrubber
    -- -------------------------------------------------------------------------
    signal scrub_ptr       : natural range 0 to MEM_DEPTH - 1;
    signal scrub_advance   : std_ulogic; -- request pointer increment
    signal scrub_parity    : std_ulogic; -- computed parity of latched data
    signal scrub_par_error : std_ulogic; -- mismatch: computed vs stored

    -- -------------------------------------------------------------------------
    -- ECC RAM FOR PARITY
    -- -------------------------------------------------------------------------
    type ecc_t is array (0 to MEM_DEPTH - 1) of std_ulogic;
    signal ecc_ram    : ecc_t := (others => '0');
    signal ecc_wr_en  : std_ulogic; -- scrubber write enable
    signal ecc_stored : std_ulogic; -- stored parity at scrub_ptr

    -- -------------------------------------------------------------------------
    -- CPU write signals
    -- -------------------------------------------------------------------------
    signal cpu_writing   : std_ulogic;
    signal cpu_word_addr : natural range 0 to MEM_DEPTH - 1;
    signal cpu_parity    : std_ulogic; -- computed parity of cpu data

    -- -------------------------------------------------------------------------
    -- Cpu Scrubber conflict detection
    -- -------------------------------------------------------------------------
    signal conflict : std_ulogic;

begin

    -- -------------------------------------------------------------------------
    -- Static wiring
    -- -------------------------------------------------------------------------
    mem_addr_b_o    <= std_ulogic_vector(to_unsigned(scrub_ptr, AWIDTH - 2));
    mem_data_b_o    <= mem_data_b_i;
    ecc_stored      <= ecc_ram(scrub_ptr);
    scrub_parity    <= compute_parity(mem_data_b_i);
    scrub_par_error <= '1' when (scrub_parity /= ecc_stored) else
        '0';

    -- -------------------------------------------------------------------------
    -- Conflict detection
    -- -------------------------------------------------------------------------
    cpu_writing <= '1' when (cpu_en_i /= "0000") and (cpu_rw_i = '1') else
        '0';
    cpu_word_addr <= to_integer(unsigned(cpu_addr_i));
    conflict      <= '1' when (cpu_writing = '1') and
        (cpu_word_addr = scrub_ptr) else
        '0';
    cpu_parity <= compute_parity(cpu_data_i);

    -- -------------------------------------------------------------------------
    -- ECC parity store write - CPU has priority, then scrubber
    -- -------------------------------------------------------------------------
    p_ecc_write : process (clk_i)
    begin
        if rising_edge(clk_i) then
            if (cpu_writing = '1') then
                ecc_ram(cpu_word_addr) <= cpu_parity;
            elsif (ecc_wr_en = '1') then
                ecc_ram(scrub_ptr) <= scrub_parity;
            end if;
        end if;
    end process p_ecc_write;

    -- -------------------------------------------------------------------------
    -- FSM sequential: state register
    -- -------------------------------------------------------------------------
    p_seq : process (rstn_i, clk_i)
    begin
        -- asynchronous reset as neorv32
        if (rstn_i = '0') then
            current_state <= S_IDLE;
            scrub_ptr     <= 0;

        elsif rising_edge(clk_i) then
            current_state <= next_state;

            -- pointer increment
            if (scrub_advance = '1') then
                if (scrub_ptr = MEM_DEPTH - 1) then
                    scrub_ptr <= 0;
                else
                    scrub_ptr <= scrub_ptr + 1;
                end if;
            end if;

        end if;
    end process p_seq;

    -- -------------------------------------------------------------------------
    -- FSM combinational: next state and outputs
    -- -------------------------------------------------------------------------
    p_comb : process (current_state, conflict, scrub_par_error, scrubber_en)
    begin
        -- safe defaults
        next_state       <= current_state;
        mem_en_b_o       <= '0';
        mem_rw_b_o       <= '0';
        stat_error_det_o <= '0';
        stat_error_fix_o <= '0';
        ecc_wr_en        <= '0';
        scrub_advance    <= '0';

        case current_state is

            when S_IDLE =>
                -- active after scrubber is enabled
                if (scrubber_en = '1') then
                    next_state <= S_READ;
                end if;

            when S_READ =>
                -- stall until conflict passes (a scrubber read would get either old data or the data from cpu wr operation)
                if (conflict = '0') then
                    mem_en_b_o <= '1';
                    next_state <= S_CHECK;
                end if;

            when S_CHECK =>
                -- go to read until conflict passes (a pass to S_WRITE would overwrite the previous cpu wr operation)
                if (conflict = '1') then
                    next_state <= S_READ;
                elsif (scrub_par_error = '0') then
                    scrub_advance <= '1';
                    next_state    <= S_READ;
                else
                    stat_error_det_o <= '1';
                    next_state       <= S_WRITE;
                end if;

            when S_WRITE =>
                -- go to read until conflict passes (would issue wr transaction on same addr for both cpu and scrubber)
                if (conflict = '1') then
                    next_state <= S_READ;
                else
                    mem_en_b_o       <= '1';
                    mem_rw_b_o       <= '1';
                    ecc_wr_en        <= '1';
                    scrub_advance    <= '1';
                    stat_error_fix_o <= '1';
                    next_state       <= S_READ;
                end if;

            when others =>
                next_state <= S_IDLE;

        end case;
    end process p_comb;

    -- -------------------------------------------------------------------------
    -- Status outputs
    -- -------------------------------------------------------------------------
    stat_state_o <= "000" when current_state = S_IDLE else
        "001" when current_state = S_READ else
        "010" when current_state = S_CHECK else
        "011" when current_state = S_WRITE else
        "111";

    stat_ptr_o      <= std_ulogic_vector(to_unsigned(scrub_ptr, AWIDTH - 2));
    stat_conflict_o <= conflict;
    stat_busy_o     <= '0' when current_state = S_IDLE else
        '1';
    stat_full_pass_o <= '1' when (scrub_advance = '1') and
        (scrub_ptr = MEM_DEPTH - 1) else
        '0';
end neorv32_scrub_fsm_rtl;