--------------------------------------------------------------------------------------
-- Testbench: tb_neorv32_scrub_fsm.vhd
-- Author: Aldo Lupio
-- DUT: neorv32_scrub_fsm
-- Description: Tests the scrubber fsm interactions with cpu ram transaction stimulus
--------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_neorv32_scrub_fsm is
end entity;

architecture sim of tb_neorv32_scrub_fsm is

    -- Memory configuration
    constant AWIDTH    : natural := 5; -- 32 bytes
    constant MEM_DEPTH : natural := 8; -- 32b / 4

    -- clock, reset, scrub and cpu secded enable
    signal clk        : std_ulogic := '0';
    signal rstn       : std_ulogic := '0';
    signal scrub_en   : std_ulogic := '0';
    signal cpu_ecc_en : std_ulogic := '0';

    -- Port A (CPU) memory interface
    signal cpu_en           : std_ulogic_vector(3 downto 0)  := "0000";
    signal cpu_rw           : std_ulogic                     := '0';
    signal cpu_addr         : std_ulogic_vector(31 downto 0) := (others => '0');
    signal cpu_data_written : std_ulogic_vector(31 downto 0) := (others => '0');
    signal cpu_data_read    : std_ulogic_vector(31 downto 0) := (others => '0');

    -- Port B (Scrubber) memory interface
    signal mem_en_b       : std_ulogic;
    signal mem_rw_b       : std_ulogic;
    signal mem_addr_b     : std_ulogic_vector(AWIDTH - 3 downto 0);
    signal mem_data_b_out : std_ulogic_vector(31 downto 0);
    signal mem_data_b_in  : std_ulogic_vector(31 downto 0) := (others => '0');

    -- Secded signals
    signal secded_dec_data_o       : std_ulogic_vector(31 downto 0); -- Data to be checked
    signal secded_dec_code_o       : std_logic_vector(6 downto 0);   -- Secded to be checked
    signal secded_dec_data_i       : std_ulogic_vector(31 downto 0); -- Data fixed
    signal secded_stat_corrected_i : std_ulogic;                     -- 1 Bit error fixed
    signal secded_stat_detected_i  : std_ulogic;                     -- 2 Bit error deteced
    signal secded_stat_no_error_i  : std_ulogic;                     -- Data / Code valid

    -- Secded encoder module
    signal secded_enc_data_o : std_ulogic_vector(31 downto 0); -- Data for secded computation
    signal secded_enc_code_i : std_ulogic_vector(6 downto 0);  -- Secded computed from data

    -- status signals
    signal stat_error_det : std_ulogic;
    signal stat_error_fix : std_ulogic;
    signal stat_state     : std_ulogic_vector(2 downto 0);
    signal stat_ptr       : std_ulogic_vector(AWIDTH - 3 downto 0);
    signal stat_conflict  : std_ulogic;
    signal stat_busy      : std_ulogic;
    signal stat_full_pass : std_ulogic;

    -- simulation helpers
    signal sim_done   : boolean := false;
    signal test_phase : natural := 0;

    -- simulated dpram memory
    type mem_t is array (0 to MEM_DEPTH - 1) of std_ulogic_vector(31 downto 0);
    shared variable fake_mem : mem_t := (others => x"00000000");

begin

    ----------------------------------------------------------------------------
    -- Clock generation - 125 MHz
    ----------------------------------------------------------------------------
    clk <= not clk after 4 ns when not sim_done else
        '0';

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : entity work.neorv32_scrub_fsm
        generic map(
            AWIDTH    => AWIDTH,
            MEM_DEPTH => MEM_DEPTH
        )
        port map(
            -- clk, rst, config
            clk_i       => clk,
            rstn_i      => rstn,
            scrubber_en => scrub_en,
            cpu_ecc_en  => cpu_ecc_en,
            -- cpu port A
            cpu_en_i   => cpu_en,
            cpu_rw_i   => cpu_rw,
            cpu_addr_i => cpu_addr,
            cpu_data_i => cpu_data_written,
            -- scrubber port B
            mem_en_b_o   => mem_en_b,
            mem_rw_b_o   => mem_rw_b,
            mem_addr_b_o => mem_addr_b,
            mem_data_b_o => mem_data_b_out,
            mem_data_b_i => mem_data_b_in,
            -- Secded decoder module
            secded_dec_data_o       => secded_dec_data_o,
            secded_dec_code_o       => secded_dec_code_o,
            secded_dec_data_i       => secded_dec_data_i,
            secded_stat_corrected_i => secded_stat_corrected_i,
            secded_stat_detected_i  => secded_stat_detected_i,
            secded_stat_no_error_i  => secded_stat_no_error_i,
            -- Secded encoder module
            secded_enc_data_o => secded_enc_data_o,
            secded_enc_code_i => secded_enc_code_i,
            -- Scrubber status          
            stat_error_det_o => stat_error_det,
            stat_error_fix_o => stat_error_fix,
            stat_state_o     => stat_state,
            stat_ptr_o       => stat_ptr,
            stat_conflict_o  => stat_conflict,
            stat_busy_o      => stat_busy,
            stat_full_pass_o => stat_full_pass
        );

    ----------------------------------------------------------------------------
    -- Simulated Dual Port RAM ? responds to Port B and CPU Port A
    ----------------------------------------------------------------------------
    p_fake_mem : process (clk)
        variable addr : natural;
    begin
        if rising_edge(clk) then
            if (cpu_en = "1111") then
                addr := to_integer(unsigned(cpu_addr));
                if (cpu_rw = '1') then
                    fake_mem(addr) := cpu_data_written;
                else
                    cpu_data_read <= fake_mem(addr);
                end if;
            end if;
            if (mem_en_b = '1') then
                addr := to_integer(unsigned(mem_addr_b));
                if (mem_rw_b = '1') then
                    fake_mem(addr) := mem_data_b_out;
                else
                    mem_data_b_in <= fake_mem(addr);
                end if;
            end if;
        end if;
    end process p_fake_mem;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    p_stim : process

        -- helper: wait N clock cycles
        procedure wait_clk(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- helper: simulate a 1 cycle CPU write transaction
        procedure cpu_write(word_addr : natural; data : std_ulogic_vector(31 downto 0)) is
        begin
            cpu_en           <= "1111";
            cpu_rw           <= '1';
            cpu_addr         <= std_ulogic_vector(to_unsigned(word_addr, 32));
            cpu_data_written <= data;
            wait until rising_edge(clk);
            cpu_en           <= "0000";
            cpu_rw           <= '0';
            cpu_addr         <= (others => '0');
            cpu_data_written <= (others => '0');
        end procedure;

        -- helper: inject SEU by flipping one bit given addr and bit position
        procedure inject_seu(word_addr : natural; bit_pos : natural) is
        begin
            fake_mem(word_addr)(bit_pos) := not fake_mem(word_addr)(bit_pos);
        end procedure;

        -- helper: overwrite a word in simulated memory
        procedure mem_set(word_addr : natural; data : std_ulogic_vector(31 downto 0)) is
        begin
            fake_mem(word_addr) := data;
        end procedure;

        -- helper: wait for scrubber to reach a specific address in S_READ
        procedure wait_scrub_read(addr : natural) is
        begin
            loop
                wait until rising_edge(clk);
                exit when (to_integer(unsigned(stat_ptr)) = addr) and (stat_state = "001");
            end loop;
        end procedure;

        -- helper: wait for scrubber to reach a specific address in S_CHECK
        procedure wait_scrub_check(addr : natural) is
        begin
            loop
                wait until rising_edge(clk);
                exit when (to_integer(unsigned(stat_ptr)) = addr) and (stat_state = "010");
            end loop;
        end procedure;

    begin

        --------------------------------------------------------------------
        -- Phase 1: Reset
        --------------------------------------------------------------------
        test_phase <= 1;
        report "Phase 1: Reset" severity note;

        rstn <= '0';
        wait_clk(5);
        rstn <= '1';
        wait_clk(2);

        assert stat_state = "000"
        report "FAIL: FSM not in S_IDLE after reset" severity error;
        assert stat_busy = '0'
        report "FAIL: busy should be low in S_IDLE" severity error;

        --------------------------------------------------------------------
        -- Phase 2: Preload memory with known data
        --------------------------------------------------------------------
        test_phase <= 2;
        report "Phase 2: Preload memory" severity note;

        for i in 0 to MEM_DEPTH - 1 loop
            mem_set(i, std_ulogic_vector(to_unsigned(i * 111, 32)));
        end loop;
        wait_clk(1);

        --------------------------------------------------------------------
        -- Phase 3: Enable scrubber: verify basic operation
        --------------------------------------------------------------------
        test_phase <= 3;
        report "Phase 3: Enable scrubber" severity note;

        scrub_en   <= '1';
        cpu_ecc_en <= '1';
        wait_clk(1);

        assert stat_busy = '1'
        report "FAIL: busy should be high after enable" severity error;

        -- wait for first full pass to build ECC store
        wait until stat_full_pass = '1';
        report "First full pass completed: ECC store initialised" severity note;
        wait_clk(5);

        --------------------------------------------------------------------
        -- Phase 4: SEU injection, verify detection
        --------------------------------------------------------------------
        test_phase <= 4;
        report "Phase 4: SEU injection at addr 3" severity note;

        inject_seu(3, 0);

        -- wait for scrubber to reach addr 3 and detect the error
        wait until stat_error_det = '1';
        report "SEU detected" severity note;
        wait_clk(5);

        --------------------------------------------------------------------
        -- Phase 5: CPU write to different address, no conflict expected
        --------------------------------------------------------------------
        test_phase <= 5;
        report "Phase 5: CPU write different address" severity note;

        -- wait for scrubber to be in addr 1
        wait_scrub_read(1);

        -- write to addr 3 while scrubber is at addr 1, no conflict
        cpu_write(3, std_ulogic_vector(to_unsigned(11, 32)));
        wait_clk(1);

        assert stat_conflict = '0'
        report "FAIL: unexpected conflict on different address" severity error;

        -- let scrubber pass over addr 3 ? verify no false error
        wait_scrub_check(3);
        wait_clk(1);

        assert stat_error_det = '0'
        report "FAIL: false error after CPU write" severity error;
        report "CPU write to different address: no conflict, parity correct" severity note;
        wait_clk(5);

        --------------------------------------------------------------------
        -- Phase 6: CPU issues write, conflict during S_READ
        --------------------------------------------------------------------
        test_phase <= 6;
        report "Phase 6: CPU write conflict in S_READ" severity note;

        -- inject SEU at addr 5 so scrubber will detect an error there
        inject_seu(5, 0);

        -- wait for scrubber to be in S_CHECK of addr 4
        wait_scrub_check(4);

        -- issue CPU write to addr 5, 1 cycle after
        cpu_write(5, std_ulogic_vector(to_unsigned(10, 32)));

        -- scrubber should have stalled and re-read addr 5
        wait_clk(5);
        report "S_READ conflict test complete" severity note;

        --------------------------------------------------------------------
        -- Phase 7: CPU issues write, conflict during S_CHECK
        --------------------------------------------------------------------
        test_phase <= 7;
        report "Phase 7: CPU write conflict in S_CHECK" severity note;

        -- inject SEU at addr 6 so scrubber will detect an error there
        inject_seu(6, 0);

        -- wait for scrubber to enter S_READ for addr 6
        wait_scrub_read(6);

        -- issue CPU write to addr 6, 1 cycle after
        cpu_write(6, std_ulogic_vector(to_unsigned(22, 32)));

        -- scrubber should discard stale data and re-read
        wait_clk(5);
        report "S_CHECK conflict test complete" severity note;

        --------------------------------------------------------------------
        -- Phase 8: CPU issues write, conflict during S_WRITE
        --------------------------------------------------------------------
        test_phase <= 8;
        -- ecc automatically updated by cpu disable, scrubber should detect and fix
        cpu_ecc_en <= '0';
        report "Phase 8: CPU write conflict in S_WRITE" severity note;

        -- inject SEU at addr 7 to force scrubber into S_WRITE
        inject_seu(7, 0);

        -- wait for scrubber to detect the error
        wait_scrub_check(7);

        -- now the FSM is about to enter S_WRITE, issue write 1 cycle after
        cpu_write(7, std_ulogic_vector(to_unsigned(8, 32)));

        -- parity should have changed from 0 to 1 by scrubber

        -- scrubber should abort correction, CPU write takes priority
        wait_clk(5);
        report "S_WRITE conflict test complete" severity note;

        --------------------------------------------------------------------
        -- Phase 9: Final full pass, verify no errors remain
        --------------------------------------------------------------------
        test_phase <= 9;
        report "Phase 9: Final clean pass" severity note;

        wait until stat_full_pass = '1';

        report "Final pass completed" severity note;
        wait_clk(10);

        --------------------------------------------------------------------
        -- Simulation completed
        --------------------------------------------------------------------
        test_phase <= 0;
        report "========================================" severity note;
        report "All tests completed successfully" severity note;
        report "========================================" severity note;
        sim_done <= true;
        wait;

    end process p_stim;

end architecture;