-- -------------------------------------------------------------------------------- --
-- Testbench   : tb_neorv32_scrub_fsm                                                --
-- Author      : Aldo Lupio                                                          --
-- DUT         : neorv32_scrub_fsm                                                   --
-- Description : Tests scrubber FSM with SECDED, byte addressing, and fault log.     --
--               Phases 1 to 6 nominal, phases 7 to 9 CPU write conflicts.           --
--               Ordered simple to complex.                                          --
-- -------------------------------------------------------------------------------- --
-- FSM state encoding (stat_state_o):                                                --
--   000 S_IDLE   001 S_ISSUE_READ   010 S_REG_READ   011 S_DECODE                   --
--   100 S_CHECK  101 S_REG_ENCODE   110 S_ISSUE_WRITE                               --
-- -------------------------------------------------------------------------------- --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;

entity tb_neorv32_scrub_fsm is
end entity;

architecture sim of tb_neorv32_scrub_fsm is

    -- Memory configuration
    constant DMEM_AWIDTH : natural := 5; -- 5-bit byte address (32 bytes)
    constant DMEM_DEPTH  : natural := 8; -- 8 words of 32 bits

    -- Scrubber start / end memory word addresses
    constant C_SCRUB_START : natural := 0;
    constant C_SCRUB_END   : natural := 6;

    -- FSM state codes (match stat_state_o encoding)
    constant ST_IDLE       : std_ulogic_vector(2 downto 0) := "000";
    constant ST_ISSUE_READ : std_ulogic_vector(2 downto 0) := "001";
    constant ST_REG_READ   : std_ulogic_vector(2 downto 0) := "010";
    constant ST_DECODE     : std_ulogic_vector(2 downto 0) := "011";
    constant ST_CHECK      : std_ulogic_vector(2 downto 0) := "100";
    constant ST_REG_ENCODE : std_ulogic_vector(2 downto 0) := "101";
    constant ST_ISSUE_WR   : std_ulogic_vector(2 downto 0) := "110";

    -- Global control
    signal clk      : std_ulogic := '0';
    signal rstn     : std_ulogic := '0';
    signal scrub_en : std_ulogic := '0';

    -- CPU write monitoring
    signal cpu_ben     : std_ulogic_vector(3 downto 0)               := "0000";
    signal cpu_rw      : std_ulogic                                  := '0';
    signal cpu_addr    : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0) := (others => '0');
    signal cpu_data_wr : std_ulogic_vector(31 downto 0)              := (others => '0');
    signal cpu_data_rd : std_ulogic_vector(31 downto 0)              := (others => '0');

    -- DMEM port B (scrubber)
    signal scrub_en_b   : std_ulogic;
    signal scrub_rw_b   : std_ulogic;
    signal scrub_addr_b : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal scrub_data_o : std_ulogic_vector(31 downto 0);
    signal scrub_data_i : std_ulogic_vector(31 downto 0) := (others => '0');

    -- Fault log
    signal flog_clear     : std_ulogic := '0';
    signal flog_last_addr : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal flog_count     : std_ulogic_vector(7 downto 0);
    signal flog_overflow  : std_ulogic;

    -- Status
    signal stat_data_valid : std_ulogic;
    signal stat_corrected  : std_ulogic;
    signal stat_detected   : std_ulogic;
    signal stat_state      : std_ulogic_vector(2 downto 0);
    signal stat_addr       : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal stat_conflict   : std_ulogic;
    signal stat_busy       : std_ulogic;
    signal stat_full_pass  : std_ulogic;

    -- Simulation control
    signal sim_done   : boolean := false;
    signal test_phase : natural := 0;

    -- Conflict mechanism observation: latches if stat_conflict was ever high
    signal conflict_seen : std_ulogic := '0';
    signal conflict_arm  : std_ulogic := '0';

    -- Simulated dual-port RAM
    type mem_t is array (0 to DMEM_DEPTH - 1) of std_ulogic_vector(31 downto 0);
    shared variable fake_mem : mem_t := (others => x"00000000");

begin

    -- -------------------------------------------------------------------------
    -- Clock generation (125 MHz)
    -- -------------------------------------------------------------------------
    clk <= not clk after 4 ns when not sim_done else
        '0';

    -- -------------------------------------------------------------------------
    -- DUT
    -- -------------------------------------------------------------------------
    dut : entity neorv32.neorv32_scrub_fsm
        generic map(
            DMEM_AWIDTH => DMEM_AWIDTH,
            DMEM_DEPTH  => DMEM_DEPTH,
            SCRUB_START => C_SCRUB_START,
            SCRUB_END   => C_SCRUB_END
        )
        port map(
            clk_i             => clk,
            rstn_i            => rstn,
            scrub_en_i        => scrub_en,
            cpu_ben_i         => cpu_ben,
            cpu_rw_i          => cpu_rw,
            cpu_addr_i        => cpu_addr,
            cpu_data_i        => cpu_data_wr,
            scrub_en_o        => scrub_en_b,
            scrub_rw_o        => scrub_rw_b,
            scrub_addr_o      => scrub_addr_b,
            scrub_data_o      => scrub_data_o,
            scrub_data_i      => scrub_data_i,
            flog_clear_i      => flog_clear,
            flog_last_addr_o  => flog_last_addr,
            flog_count_o      => flog_count,
            flog_overflow_o   => flog_overflow,
            stat_data_valid_o => stat_data_valid,
            stat_corrected_o  => stat_corrected,
            stat_detected_o   => stat_detected,
            stat_state_o      => stat_state,
            stat_addr_o       => stat_addr,
            stat_conflict_o   => stat_conflict,
            stat_busy_o       => stat_busy,
            stat_full_pass_o  => stat_full_pass
        );

    -- -------------------------------------------------------------------------
    -- Simulated dual port BRAM (port A for CPU, port B for scrubber)
    -- Addresses are byte addresses, word index = addr / 4
    -- One cycle synchronous read latency.
    -- -------------------------------------------------------------------------
    p_fake_mem : process (clk)
        variable idx : natural;
    begin
        if rising_edge(clk) then
            -- Port A (CPU)
            if (cpu_ben = "1111") then
                idx := to_integer(unsigned(cpu_addr(DMEM_AWIDTH - 1 downto 2)));
                if (cpu_rw = '1') then
                    fake_mem(idx) := cpu_data_wr;
                else
                    cpu_data_rd <= fake_mem(idx);
                end if;
            end if;
            -- Port B (Scrubber)
            if (scrub_en_b = '1') then
                idx := to_integer(unsigned(scrub_addr_b(DMEM_AWIDTH - 1 downto 2)));
                if (scrub_rw_b = '1') then
                    fake_mem(idx) := scrub_data_o;
                else
                    scrub_data_i <= fake_mem(idx);
                end if;
            end if;
        end if;
    end process p_fake_mem;

    -- -------------------------------------------------------------------------
    -- Conflict observer
    -- Latches conflict_seen high if stat_conflict pulses while armed.
    -- -------------------------------------------------------------------------
    p_conflict_obs : process (clk)
    begin
        if rising_edge(clk) then
            if (conflict_arm = '0') then
                conflict_seen <= '0';
            elsif (stat_conflict = '1') then
                conflict_seen <= '1';
            end if;
        end if;
    end process p_conflict_obs;

    -- -------------------------------------------------------------------------
    -- Stimulus
    -- -------------------------------------------------------------------------
    p_stim : process

        -- Wait N clock cycles
        procedure wait_clk(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Simulate a 1-cycle CPU write using byte address
        procedure cpu_write(word_idx : natural; data : std_ulogic_vector(31 downto 0)) is
        begin
            cpu_ben     <= "1111";
            cpu_rw      <= '1';
            cpu_addr    <= std_ulogic_vector(to_unsigned(word_idx * 4, DMEM_AWIDTH));
            cpu_data_wr <= data;
            wait until rising_edge(clk);
            cpu_ben     <= "0000";
            cpu_rw      <= '0';
            cpu_addr    <= (others => '0');
            cpu_data_wr <= (others => '0');
        end procedure;

        -- Inject SEU by flipping a bit directly in fake_mem
        procedure inject_seu(word_idx : natural; bit_pos : natural) is
        begin
            fake_mem(word_idx)(bit_pos) := not fake_mem(word_idx)(bit_pos);
            report "SEU injected: word " & integer'image(word_idx) &
                " bit " & integer'image(bit_pos) severity note;
        end procedure;

        -- Inject double-bit error
        procedure inject_dbu(word_idx : natural; bit_a : natural; bit_b : natural) is
        begin
            fake_mem(word_idx)(bit_a) := not fake_mem(word_idx)(bit_a);
            fake_mem(word_idx)(bit_b) := not fake_mem(word_idx)(bit_b);
            report "DBU injected: word " & integer'image(word_idx) &
                " bits " & integer'image(bit_a) & "," & integer'image(bit_b)
                severity note;
        end procedure;

        -- Wait for the scrubber to reach a given word index in a given state
        procedure wait_scrub_state(word_idx : natural;
        st                                  : std_ulogic_vector(2 downto 0)) is
    begin
        loop
            wait until rising_edge(clk);
            exit when (to_integer(unsigned(stat_addr(DMEM_AWIDTH - 1 downto 2))) = word_idx)
            and (stat_state = st);
        end loop;
    end procedure;

    -- Wait for a status strobe to go high
    procedure wait_strobe(signal s : std_ulogic) is
    begin
        loop
            wait until rising_edge(clk);
            exit when s = '1';
        end loop;
    end procedure;

    -- Check a memory word holds an expected value
    procedure check_mem(word_idx : natural;
    expected                     : std_ulogic_vector(31 downto 0);
    tag                          : string) is
begin
    assert fake_mem(word_idx) = expected
    report "FAIL [" & tag & "]: word " & integer'image(word_idx) &
        " mismatch" severity error;
end procedure;

begin

-- ---------------------------------------------------------------------
-- Phase 1: Reset - FSM must land in S_IDLE
-- ---------------------------------------------------------------------
test_phase <= 1;
report "Phase 1: Reset" severity note;

rstn <= '0';
wait_clk(5);
rstn <= '1';
wait_clk(2);

assert stat_state = ST_IDLE
report "FAIL: FSM not in S_IDLE after reset" severity error;
assert stat_busy = '0'
report "FAIL: busy should be low in S_IDLE" severity error;

-- ---------------------------------------------------------------------
-- Phase 2: CPU write path - preload memory and secded store
-- ---------------------------------------------------------------------
test_phase <= 2;
report "Phase 2: Preload memory via CPU writes" severity note;

for i in 0 to DMEM_DEPTH - 1 loop
    cpu_write(i, std_ulogic_vector(to_unsigned(i * 111, 32)));
    wait_clk(1);
end loop;
wait_clk(3); -- let the CPU encode pipeline drain into the ECC store

-- ---------------------------------------------------------------------
-- Phase 3: Enable scrubber, wait for the first full pass
-- ---------------------------------------------------------------------
test_phase <= 3;
report "Phase 3: Enable scrubber, wait for first full pass" severity note;

scrub_en <= '1';

wait_strobe(stat_full_pass);
report "First full pass completed: ECC store consistent" severity note;

assert stat_detected = '0'
report "FAIL: unexpected detected error during clean pass" severity error;
wait_clk(5);

-- ---------------------------------------------------------------------
-- Phase 4: Single bit error - expect correction
-- ---------------------------------------------------------------------
test_phase <= 4;
report "Phase 4: Single bit SEU at word 3, bit 0" severity note;

inject_seu(3, 0);

wait_strobe(stat_corrected);
report "Single bit error corrected by scrubber" severity note;

wait_strobe(stat_full_pass);
check_mem(3, std_ulogic_vector(to_unsigned(3 * 111, 32)), "P4");
wait_clk(5);

-- ---------------------------------------------------------------------
-- Phase 5: Double bit error - expect detection and fault log
-- ---------------------------------------------------------------------
test_phase <= 5;
report "Phase 5: Double bit error at word 1, bits 0 and 1" severity note;

inject_dbu(1, 0, 1);

wait_strobe(stat_detected);
report "Double bit error detected by scrubber" severity note;
wait_clk(2);

assert flog_count /= x"00"
report "FAIL: fault log count did not increment on detect" severity error;
report "Fault log count = " &
    integer'image(to_integer(unsigned(flog_count))) severity note;
wait_clk(5);

-- ---------------------------------------------------------------------
-- Phase 6: Fault log clear
-- ---------------------------------------------------------------------
test_phase <= 6;
report "Phase 6: Clear fault log" severity note;

flog_clear <= '1';
wait_clk(1);
flog_clear <= '0';
wait_clk(1);

assert flog_count = x"00"
report "FAIL: fault log count not cleared" severity error;
assert flog_overflow = '0'
report "FAIL: fault log overflow not cleared" severity error;
wait_clk(5);

-- ---------------------------------------------------------------------
-- Phase 7: CPU write conflict during the S_REG_READ phase
-- CPU writes the word while the scrubber is in S_REG_READ on it.
-- Expectation: conflict re-issues the read, CPU data survives.
-- ---------------------------------------------------------------------
test_phase <= 7;
report "Phase 7: CPU write conflict during S_REG_READ phase (word 4)" severity note;

conflict_arm <= '1';
wait_scrub_state(4, ST_ISSUE_READ);
cpu_write(4, std_ulogic_vector(to_unsigned(444, 32)));

wait_strobe(stat_full_pass);
conflict_arm <= '0';

-- mechanism: conflict must have fired
assert conflict_seen = '1'
report "FAIL [P7]: conflict never asserted on S_REG_READ conflict" severity error;
-- value: CPU data must survive
check_mem(4, std_ulogic_vector(to_unsigned(444, 32)), "P7");
report "Read conflict: conflict fired, CPU data preserved" severity note;
wait_clk(5);

-- ---------------------------------------------------------------------
-- Phase 8: CPU write conflict during the S_REG_ENCODE phase
-- Inject an SEU first so the scrubber actually has work, then write
-- the same word while it is in S_REG_ENCODE. abort_writeback must fire.
-- ---------------------------------------------------------------------
test_phase <= 8;
report "Phase 8: CPU write conflict during S_REG_ENCODE phase (word 5)" severity note;

conflict_arm <= '1';
inject_seu(5, 0);
wait_scrub_state(5, ST_CHECK);
cpu_write(5, std_ulogic_vector(to_unsigned(555, 32)));

wait_strobe(stat_full_pass);
conflict_arm <= '0';

-- mechanism: conflict must have fired
assert conflict_seen = '1'
report "FAIL [P8]: conflict never asserted on S_REG_ENCODE conflict" severity error;
-- value: writeback dropped, CPU data must survive
check_mem(5, std_ulogic_vector(to_unsigned(555, 32)), "P8");
report "Check conflict: conflict fired, writeback dropped, CPU data preserved"
    severity note;
wait_clk(5);

-- ---------------------------------------------------------------------
-- Phase 9: CPU write conflict during the S_CHECK phase
-- Inject an SEU so the scrubber reaches S_CHECK
-- Scrubber must restart to S_ISSUE_READ
-- ---------------------------------------------------------------------
test_phase <= 9;
report "Phase 9: CPU write conflict during S_CHECK phase (word 6)" severity note;

-- although state is ST_DECODE, it has a delay of 1 cycle so its at S_CHECK of diff addr
conflict_arm <= '1';
inject_seu(6, 0);
wait_scrub_state(6, ST_DECODE);
cpu_write(6, std_ulogic_vector(to_unsigned(666, 32)));

wait_strobe(stat_full_pass);
conflict_arm <= '0';

-- mechanism: conflict must have fired
assert conflict_seen = '1'
report "FAIL [P9]: conflict never asserted on S_ISSUE_READ conflict"
    severity error;
-- value: scrubber must NOT overwrite the CPU data
check_mem(6, std_ulogic_vector(to_unsigned(666, 32)), "P9");
report "S_CHECK conflict: conflict fired, CPU data preserved" severity note;
wait_clk(10);

-- ---------------------------------------------------------------------
-- Done
-- ---------------------------------------------------------------------
test_phase <= 0;
report "========================================" severity note;
report "All tests completed" severity note;
report "========================================" severity note;
sim_done <= true;
wait;

end process p_stim;

end architecture;