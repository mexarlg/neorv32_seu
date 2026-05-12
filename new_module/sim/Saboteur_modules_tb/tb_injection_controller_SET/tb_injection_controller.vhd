--==============================================================================
--  Testbench   : Fault Injection Controller Testbench
--  File        : tb_fault_injection_controller.vhd
--
--  Description :
--      Testbench for the fault_injection_controller module.
--
--      The DUT generates a probabilistic match signal based on the comparison
--      of the least significant bits of two internal LFSRs. The number of bits
--      compared (nbr_bits_to_match) controls the injection probability:
--
--          P(match) = 1 / 2^N   with N = nbr_bits_to_match
--
--      This testbench validates:
--          - deterministic behavior (100% and 0% match cases)
--          - correct disabling of the module via fault_enable
--          - statistical correctness of the generated match rate
--
--  Tests:
--      TEST 1:
--          Verifies 100% match rate when nbr_bits_to_match = 0.
--
--      TEST 2:
--          Verifies match is always '0' when fault_enable = '0'.
--
--      TEST 3:
--          Verifies statistical correctness of match probability for
--          nbr_bits_to_match in [1..15], using a large number of samples.
--
--  Methodology:
--      - A 16-bit LFSR is used in the testbench to generate pseudo-random
--        values for dynamic test conditions.
--      - Statistical validation is performed by measuring the observed rate
--        of match events and comparing it to the theoretical probability.
--      - A tolerance EPSILON is used to validate convergence.
--
--  Author      : Olivier Oribes
--  Created     : 28/04/2026
--  Last update : 29/04/2026
--
--  Version     : 1.1
--
--  Project     : Neorv32_SEU
--  Language    : VHDL-2008
--
--  Dependencies:
--      - fault_injection_controller.vhd
--
--  Notes:
--      - This testbench assumes maximal-length LFSRs inside the DUT.
--      - Large sample size (N = 1_000_000) is used for statistical accuracy.
--      - Compile with VHDL-2008 support.
--
--  License     : MIT
--==============================================================================

library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;


entity tb_fault_injection_controller is
end entity tb_fault_injection_controller;

architecture sim of tb_fault_injection_controller is

    -- ------------------------------------------------------------------
    -- fibo_lfsr : simple LFSR-based 16-bit pseudo-random generator
    -- seed must be non-zero
    -- ------------------------------------------------------------------
    function fibo_lfsr(seed: std_ulogic_vector(15 downto 0))
        return std_ulogic_vector is

        variable s : std_ulogic_vector(15 downto 0) := seed;
        variable b : std_ulogic;

    begin

        -- Galois LFSR taps: 16, 15, 12, 10
        b  := s(15) xor s(14) xor s(11) xor s(9);
        s  := b & s(15 downto 1);

        return s;

    end function;

    
    -- ------------------------------------------------------------------
    -- Constants / signals
    -- ------------------------------------------------------------------
    constant CLK_PERIOD      : time    := 10 ns;
    signal nbr_bits_to_match : natural range 0 to 15;
    signal clk               : std_ulogic := '0';
    signal rst_n             : std_ulogic := '1';
    signal match             : std_ulogic := '0';
    signal fault_enable      : std_ulogic;
    


begin


    -- ------------------------------------------------------------------
    -- DUT
    -- ------------------------------------------------------------------
    DUT : entity work.fault_injection_controller
        port map(
            nbr_bits_to_match => nbr_bits_to_match,
            clk               => clk,
            rst_n             => rst_n,
            match             => match,
            fault_enable      => fault_enable
        );


    -- ------------------------------------------------------------------
    -- Clock generation : 100 MHz
    -- ------------------------------------------------------------------
    clk <= not(clk) after CLK_PERIOD/2;




    -- ------------------------------------------------------------------
    -- Stimulus
    -- ------------------------------------------------------------------
    
    STIM: process

        constant seed          : std_ulogic_vector(15 downto 0) := x"A5C3";
        constant LFSR_LEN      : natural := 16;
        constant N             : natural := 1_000_000;
        constant EPSILON       : real    := 0.001;
        variable error_count   : natural := 0;
        variable rand_vect     : std_ulogic_vector(15 downto 0);
        variable expected      : std_ulogic;
        variable nbr_bits      : natural range 0 to 15;
        variable expected_rate : real;
        variable rate          : real;
        variable diff          : real;
        variable count_matched : natural;
    


    begin

        -- ----------------------------------------------------------------
        -- Init
        -- ----------------------------------------------------------------

        fault_enable           <= '1';
        rst_n                  <= '0';
        nbr_bits_to_match      <= 0;

        rand_vect   := fibo_lfsr(seed);
        
        wait until rising_edge(clk);

        rst_n      <= '1';
         
        wait until rising_edge(clk);

        -- ================================================================
        -- TEST 1 : 100 % injection fault
        -- ================================================================

        nbr_bits_to_match  <= 0;
        expected := '1';

        for i in 1 to N loop

            wait until rising_edge(clk);

            if (match /= expected) then
            
                report "ERROR: wrong value" & LF &
                        "Match equal to  : " & std_ulogic'image(match) & LF &
                        "Expected value  : " & std_ulogic'image(expected)
                        severity error;
                
                error_count := error_count + 1;

            end if;
                
        end loop;

        
        if (error_count = 0) then
            report "TEST 1 ALL passed!" 
                    severity note;

        end if;

        

        -- ================================================================
        -- TEST 2 : Fault module disable
        -- ================================================================

        fault_enable <= '0';
        expected := '0';
        
        wait until rising_edge(clk);

        for i in 1 to N loop

            rand_vect := fibo_lfsr(rand_vect);
            
            nbr_bits := to_integer(unsigned(rand_vect(7 downto 0))) mod LFSR_LEN;

            nbr_bits_to_match  <= nbr_bits;

            wait until rising_edge(clk);

            if (match /= expected) then
            
                report "ERROR: wrong value" & LF &
                        "Match equal to  : " & std_ulogic'image(match) & LF &
                        "Expected value  : " & std_ulogic'image(expected)
                        severity error;
                
                error_count := error_count + 1;

            end if;
                
        end loop;

        
        if (error_count = 0) then
            report "TEST 2 ALL passed!" 
                    severity note;

        end if;


        
        -- ================================================================
        -- TEST 3 : ??? % injection fault
        -- ================================================================

        fault_enable <= '1';
        wait until rising_edge(clk);

        for j in 1 to 15 loop
            
            expected_rate     := 1.0/real(2**j);
            count_matched     := 0;
            nbr_bits_to_match <= j;

            wait until rising_edge(clk);
    
            for i in 1 to N loop

                wait until rising_edge(clk);

                if (match = '1') then
                
                    count_matched := count_matched + 1;

                end if;
                    
            end loop;
            
            rate := real(count_matched)/real(N);
            diff := abs(rate - expected_rate);

            if (diff < EPSILON) then
            
                report  "Rate equal to  : " & real'image(rate) & LF &
                        "Expected rate value  : " & real'image(expected_rate) & LF &
                        "Relative error : " & real'image(diff) & LF & LF
                        severity note;

            else 
                         
                report "ERROR: wrong value" & LF &
                        "Rate equal to  : " & real'image(rate) & LF &
                        "Expected rate value  : " & real'image(expected_rate) & LF & 
                        "Relative error : " & real'image(diff) & LF & LF
                        severity error;
                
                error_count := error_count + 1;

            end if;

        end loop;

        
        if (error_count = 0) then
                report "TEST 3 ALL passed!" 
                        severity note;

            end if;

        

        -- ================================================================
        -- Fin de simulation
        -- ================================================================
        if error_count = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report "SIMULATION FINISHED WITH " &
                   integer'image(error_count) & " ERROR(S)"
                   severity failure;
        end if;

        report "End of simulation" severity note;
        wait;


    end process STIM;

end architecture sim;
