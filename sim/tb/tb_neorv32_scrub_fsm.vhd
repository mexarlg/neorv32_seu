-- -------------------------------------------------------------------------------- --
-- Testbench   : tb_neorv32_scrub_fsm                                                --
-- Author      : Aldo Lupio                                                          --
-- DUT         : neorv32_scrub_fsm                                                   --
-- Description : Tests scrubber FSM with SECDED, byte addressing, and fault log      --
-- -------------------------------------------------------------------------------- --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_neorv32_scrub_fsm is
end entity;

architecture sim of tb_neorv32_scrub_fsm is

    -- Memory configuration
    constant DMEM_AWIDTH : natural := 5; -- 5-bit byte address (32 bytes)
    constant DMEM_DEPTH  : natural := 8; -- 8 words of 32 bits

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
    dut : entity work.neorv32_scrub_fsm
        generic map(
            DMEM_AWIDTH => DMEM_AWIDTH,
            DMEM_DEPTH  => DMEM_DEPTH
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
    -- Simulated dual-port RAM (port A for CPU, port B for scrubber)
    -- Addresses are byte addresses, word index = addr / 4
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
        end procedure;

        -- Inject double-bit error
        procedure inject_dbu(word_idx : natural; bit_a : natural; bit_b : natural) is
        begin
            fake_mem(word_idx)(bit_a) := not fake_mem(word_idx)(bit_a);
            fake_mem(word_idx)(bit_b) := not fake_mem(word_idx)(bit_b);
        end procedure;

        -- Preload a word in fake_mem
        procedure mem_set(word_idx : natural; data : std_ulogic_vector(31 downto 0)) is
        begin
            fake_mem(word_idx) := data;
        end procedure;

        -- Wait for scrubber to reach a word index in S_READ
        procedure wait_scrub_read(word_idx : natural) is
        begin
            loop
                wait until rising_edge(clk);
                exit when (to_integer(unsigned(stat_addr(DMEM_AWIDTH - 1 downto 2))) = word_idx)
                and (stat_state = "001");
            end loop;
        end procedure;

        -- Wait for scrubber to reach a word index in S_CHECK
        procedure wait_scrub_check(word_idx : natural) is
        begin
            loop
                wait until rising_edge(clk);
                exit when (to_integer(unsigned(stat_addr(DMEM_AWIDTH - 1 downto 2))) = word_idx)
                and (stat_state = "010");
            end loop;
        end procedure;

    begin

        -- Phase 1: Reset. ok
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

        -- Phase 2: Preload memory with known data. ok
        test_phase <= 2;
        report "Phase 2: Preload memory" severity note;

        for i in 0 to DMEM_DEPTH - 1 loop
            wait_clk(1);
            cpu_write(i, std_ulogic_vector(to_unsigned(i * 111, 32)));
        end loop;
        wait_clk(1);

        -- Phase 3: Enable scrubber, wait for first full pass. ok (stat signals valid on check, same as dec)
        test_phase <= 3;
        report "Phase 3: Enable scrubber" severity note;

        scrub_en <= '1';
        wait_clk(1);

        loop
            wait until rising_edge(clk);
            exit when stat_full_pass = '1';
        end loop;

        report "First full pass completed: ECC store initialised" severity note;
        wait_clk(5);

        -- Phase 4: Single bit SEU on data addr = 3, verify correction
        test_phase <= 4;
        report "Phase 4: Single bit SEU at word 3, bit 0" severity note;

        inject_seu(3, 0);

        loop
            wait until rising_edge(clk);
            exit when stat_corrected = '1';
        end loop;
        report "Single bit error corrected" severity note;

        -- make sure the seu is fixed and not logged on the fault log
        assert flog_count = x"00"
        report "FAIL: fault log count should be 0 after correction" severity error;
        wait_clk(5);

        -- Phase 5: Double bit error, verify detection and fault log. ok
        test_phase <= 5;
        report "Phase 5: Double bit error at word 1, bits 0 and 1" severity note;

        inject_dbu(1, 0, 1);

        loop
            wait until rising_edge(clk);
            exit when stat_detected = '1';
        end loop;
        wait_clk(1);

        report "Fault log: count=" & integer'image(to_integer(unsigned(flog_count)))
            & " addr=" & integer'image(to_integer(unsigned(flog_last_addr)))
            severity note;
        wait_clk(5);

        -- Phase 6: Fault log clear
        test_phase <= 6;
        report "Phase 6: Clear fault log" severity note;

        flog_clear <= '1';
        wait_clk(1);
        flog_clear <= '0';
        wait_clk(1);

        assert flog_count = x"00"
        report "FAIL: fault log count should be 0 after clear" severity error;
        assert flog_overflow = '0'
        report "FAIL: overflow should be 0 after clear" severity error;
        wait_clk(5);

        -- Phase 7: CPU write to different address, no conflict expected
        test_phase <= 7;
        report "Phase 7: CPU write different address" severity note;

        wait_scrub_read(1);
        cpu_write(3, std_ulogic_vector(to_unsigned(11, 32)));
        wait_clk(1);

        assert stat_conflict = '0'
        report "FAIL: unexpected conflict on different address" severity error;

        wait_scrub_check(3);
        wait_clk(1);

        assert stat_corrected = '0'
        report "FAIL: false correction after CPU write" severity error;
        report "CPU write to different address: no conflict" severity note;
        wait_clk(5);

        -- Phase 8: CPU write conflict in S_READ
        test_phase <= 8;
        report "Phase 8: CPU write conflict in S_READ" severity note;

        inject_seu(5, 0);
        wait_scrub_check(4);
        cpu_write(5, std_ulogic_vector(to_unsigned(10, 32)));
        wait_clk(5);
        report "S_READ conflict test complete" severity note;

        -- Phase 9: CPU write conflict in S_CHECK
        test_phase <= 9;
        report "Phase 9: CPU write conflict in S_CHECK" severity note;

        inject_seu(6, 0);
        wait_scrub_read(6);
        cpu_write(6, std_ulogic_vector(to_unsigned(22, 32)));
        wait_clk(5);
        report "S_CHECK conflict test complete" severity note;

        -- Phase 10: CPU write conflict in S_WRITE
        test_phase <= 10;
        report "Phase 10: CPU write conflict in S_WRITE" severity note;

        inject_seu(7, 0);
        wait_scrub_check(7);
        cpu_write(7, std_ulogic_vector(to_unsigned(8, 32)));
        wait_clk(5);
        report "S_WRITE conflict test complete" severity note;

        -- Phase 11: Final pass (still a multibit on position 1)
        test_phase <= 11;

        cpu_write(5, std_ulogic_vector(to_unsigned(3, 32)));
        wait_scrub_read(4);

        report "Phase 11: Final clean pass" severity note;
        wait until stat_full_pass = '1';
        report "Final pass completed" severity note;
        wait_clk(10);

        -- Notes of testing: 

        -- The secded code should have another way of protection as the scrubber relies on it being correct

        -- Also, the scrubber state output signals are not registered, which might have combinatorial glitches
        -- Some of the status signals of the encoder/decoder are erroneous on some transition states, 
        -- but are only checked by the scrubber on the check state (when their result is valid)

        -- The fault log will continue to increase the count after it has passed a full revolution,
        -- which increases the count although the existing error is the same

        -- Done
        test_phase <= 0;
        report "========================================" severity note;
        report "All tests completed" severity note;
        report "========================================" severity note;
        sim_done <= true;
        wait;

    end process p_stim;

end architecture;