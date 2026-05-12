-- ==============================================================================
--  Module      : Fault_injection_controller
--  File        : fault_injection_controller.vhd
--
--  Description :
--      Sequential block generating a probabilistic match signal used to control
--      the injection rate of transient faults (SET) in the injection_fault module.
--
--      Two independent 16-bit Fibonacci LFSRs are updated every clock cycle when
--      fault_enable = '1'. A match is detected when their N least significant
--      bits are equal, yielding an injection probability of 1/2^N
--      (N = nbr_bits_to_match).
--
--      Special case: nbr_bits_to_match = 0 forces match = '1' when enabled,
--      modeling a 100% injection rate.
--
--  Features:
--      - Two decorrelated 16-bit Fibonacci LFSRs with distinct seeds and tap polynomials
--      - Configurable injection rate via nbr_bits_to_match (0 to 15)
--      - Injection probability : 1/2^N (N = nbr_bits_to_match)
--      - Fully synchronous with asynchronous active-low reset
--
--  Behavior:
--      - Reset behavior: match = '0', LFSRs restored to seed values
--      - If fault_enable = '0', match = '0' and LFSRs are not advanced
--      - On each rising edge of clk, if fault_enable = '1', both LFSRs are updated
--      - If the N LSBs of LFSR1 equal the N LSBs of LFSR2, match = '1'
--      - If nbr_bits_to_match = 0, match is always '1' while enabled
--
--  Author      : Olivier Oribes
--  Created     : 28/04/2026
--  Last update : 28/04/2026
--
--  Version     : 1.0
--
--  Project     : Neorv32_SEU
--  Language    : VHDL
--
--  Dependencies:
--      - injection_fault.vhd (consumes the match signal)
--
--  Generics:
--      None
--
--  Ports:
--      fault_enable      : input  - Global enable for match generation
--      clk               : input  - System clock
--      rst_n             : input  - Asynchronous active-low reset
--      nbr_bits_to_match : input  - Number of LSBs to compare (controls injection rate)
--      match             : output - Probabilistic trigger signal for fault injection
--
--  License     : MIT
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity fault_injection_controller is
    port(
        fault_enable      : in  std_ulogic;
        nbr_bits_to_match : in  natural range 0 to 15;
        clk               : in  std_ulogic;
        rst_n             : in  std_ulogic;
        match             : out std_ulogic
    );
end entity fault_injection_controller;


architecture rtl of fault_injection_controller is

    function fibo_lfsr1(seed : std_ulogic_vector(15 downto 0))
        return std_ulogic_vector is

        variable s : std_ulogic_vector(15 downto 0) := seed;
        variable b : std_ulogic;

    begin
        b := s(15) xor s(13) xor s(12) xor s(10);
        s := b & s(15 downto 1);
        return s;
    end function;


    function fibo_lfsr2(seed : std_ulogic_vector(15 downto 0))
        return std_ulogic_vector is

        variable s : std_ulogic_vector(15 downto 0) := seed;
        variable b : std_ulogic;

    begin
        b := s(15) xor s(14) xor s(12) xor s(3);
        s := b & s(15 downto 1);
        return s;
    end function;


    constant seed1 : std_ulogic_vector(15 downto 0) := x"ACE1";
    constant seed2 : std_ulogic_vector(15 downto 0) := x"1234";

begin

    random_proc : process(clk, rst_n)

        variable rand_vect1 : std_ulogic_vector(15 downto 0) := seed1;
        variable rand_vect2 : std_ulogic_vector(15 downto 0) := seed2;
        variable match_var  : std_ulogic;

    begin

        if (rst_n = '0') then

            rand_vect1 := seed1;
            rand_vect2 := seed2;
            match      <= '0';

        elsif rising_edge(clk) then

            match_var := '0';

            if (fault_enable = '1') then

                rand_vect1 := fibo_lfsr1(rand_vect1);
                rand_vect2 := fibo_lfsr2(rand_vect2);

                if (nbr_bits_to_match = 0) then

                    match_var := '1';

                elsif (rand_vect1(nbr_bits_to_match-1 downto 0) =
                      rand_vect2(nbr_bits_to_match-1 downto 0)) then

                    match_var := '1';

                end if;

            end if;

            match <= match_var;

        end if;

    end process random_proc;

end architecture rtl;