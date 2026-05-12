-- ==============================================================================
--  Module      : SEU Fault Injection Controller
--  File        : injection_fault_SEU.vhd
--
--  Description :
--      This module implements a Single Event Upset (SEU) injection mechanism
--      targeting an external synchronous RAM. It performs controlled bit-flip
--      operations by reading a memory word, modifying a single bit using a
--      pseudo-random mask, and writing the corrupted value back to memory.
--
--  Features:
--      - Pseudo-random address generation using a 32-bit LFSR
--      - Pseudo-random single-bit fault injection (bit-flip)
--      - Fully synchronous finite state machine (FSM)
--      - Compatible with single-port RAM interfaces
--
--  Behavior:
--      When fault_enable is asserted:
--          1. A pseudo-random address is generated
--          2. The corresponding memory word is read
--          3. A pseudo-random bit is flipped
--          4. The modified word is written back to the same address
--
--      The process is performed over multiple clock cycles using the following FSM:
--          IDLE → READ → MODIFY → WRITE → IDLE
--
--  Author      : Olivier Oribes
--  Created     : 30/04/2026
--  Last update : 30/04/2026
--
--  Version     : 1.0
--
--  Project     : Neorv32_SEU
--  Language    : VHDL
--
--  Generics:
--      DATA_LENGTH    : Width of the data bus (must be > 0)
--      ADDRESS_LENGTH : Width of the address bus
--      MEMORY_DEPTH   : Number of memory locations (used for address bounding)
--
--  Ports:
--      clk          : System clock (rising edge)
--      fault_enable : Enables SEU injection when asserted
--
--      -- Neorv32 RAM interface --
--      en_o   : Memory access enable
--      rw_o   : Read/Write control (0 = read, 1 = write)
--      addr_o : Address bus toward memory
--      data_o : Data to be written to memory (fault-injected)
--      data_i : Data read from memory
--
--  License     : MIT
-- ==============================================================================

library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;


entity tb_injection_fault_SEU is
end entity tb_injection_fault_SEU;


architecture sim of tb_injection_fault_SEU is

    -- ------------------------------------------------------------------
    -- pseudo_rand : simple LFSR-based 32-bit pseudo-random generator
    -- seed must be non-zero
    -- ------------------------------------------------------------------
    function fibo_lfsr(seed: std_ulogic_vector(31 downto 0))
        return std_ulogic_vector is

        variable s : std_ulogic_vector(31 downto 0) := seed;
        variable b : std_ulogic;

    begin

        -- Galois LFSR taps: 32, 22, 2, 1
        b  := s(31) xor s(21) xor s(1) xor s(0);
        s  := b & s(31 downto 1);

        return s;

    end function;
    
    function count_ones(v : std_ulogic_vector) return natural is
        variable c : natural := 0;
    begin

        for i in v'range loop

            if v(i) = '1' then
                c := c + 1;
            end if;

        end loop;

        return c;
    end function;

    -- ------------------------------------------------------------------
    -- Constant and signals
    -- ------------------------------------------------------------------
    constant N              : natural := 1000;
    constant seed           : std_ulogic_vector(31 downto 0) := x"A5C3F19B";
    constant CLK_PERIOD     : time       := 10 ns;
    constant DATA_LENGTH    : positive   := 32;
    constant ADDRESS_LENGTH : positive   := 32;
    constant MEMORY_DEPTH   : positive   := 64;
    signal clk              : std_ulogic := '0';
    signal fault_enable     : std_ulogic;
    signal en_o             : std_ulogic;
    signal rw_o             : std_ulogic;
    signal addr_o           : std_ulogic_vector(ADDRESS_LENGTH-1 downto 0);
    signal data_o           : std_ulogic_vector(DATA_LENGTH-1 downto 0);
    signal data_i           : std_ulogic_vector(DATA_LENGTH-1 downto 0);

begin


    -- ------------------------------------------------------------------
    --                              DUT
    -- ------------------------------------------------------------------
    DUT : entity work.injection_fault_SEU 
        generic map(
            DATA_LENGTH      =>  DATA_LENGTH,
            ADDRESS_LENGTH   =>  ADDRESS_LENGTH,
            MEMORY_DEPTH     =>  MEMORY_DEPTH
        )
        port map(
            clk            =>  clk,
            fault_enable   =>  fault_enable,
            en_o           =>  en_o,
            rw_o           =>  rw_o,
            addr_o         =>  addr_o,
            data_o         =>  data_o,
            data_i         =>  data_i
        );



    -- ------------------------------------------------------------------
    -- Clock 
    -- ------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2;



    -- ------------------------------------------------------------------
    -- Stimulus
    -- ------------------------------------------------------------------



    STIM: process

        variable rand_vect      : std_ulogic_vector(31 downto 0) := seed;
        variable data_in        : std_ulogic_vector(DATA_LENGTH-1 downto 0);
        variable error_count1   : natural := 0;
        variable error_count2   : natural := 0;
        variable total_error    : natural := 0;

    begin
        
    -- ------------------------------------------------------------------
    -- Initialization
    -- ------------------------------------------------------------------
    
    fault_enable <= '0';
    data_in   := rand_vect(DATA_LENGTH-1 downto 0);
    data_i    <= data_in;

    wait until rising_edge(clk);
    
    -- ================================================================
    -- TEST 1 : No injection fault
    -- ================================================================
    

    for i in 0 to N loop

        
        for j in 1 to 4 loop

            wait until rising_edge(clk);

            if (en_o /= '0') then
                report "ERROR: en_o equal " & std_ulogic'image(en_o) & LF &
                    "but should be equal to 0."
                        severity error;

                error_count1 := error_count1 + 1;
            end if;

        end loop;
    
    end loop;
    
    if (error_count1 = 0) then
            report "All TEST 1 passed." severity note;
    end if;

    -- ================================================================
    -- TEST 2 : Injection fault
    -- ================================================================
    
    fault_enable <= '1';
    
    wait until rising_edge(clk);

    
    for i in 0 to N loop

        rand_vect := fibo_lfsr(rand_vect);
        data_in   := rand_vect(DATA_LENGTH - 1 downto 0);
        data_i <= data_in;

        loop

            wait until rising_edge(clk);
            wait for 0 ns;

            exit when en_o = '1' and rw_o = '1';

        end loop;

        if (count_ones(data_in xor data_o) /= 1) then

            report "ERROR: data_o is not data_i with exactly one flipped bit. " &
                "data_i = 0x" & to_hstring(data_in) &
                ", data_o = 0x" & to_hstring(data_o)
                severity error;

            error_count2 := error_count2 + 1;
        end if;

        if (to_integer(unsigned(addr_o)) >= MEMORY_DEPTH) then

            report "ERROR: addr_o out of RAM range: " &
                integer'image(to_integer(unsigned(addr_o)))
                severity error;

            error_count2 := error_count2 + 1;
        end if;
            
    end loop;
    
    
    if (error_count2 = 0) then
            report "All TEST 2 passed." severity note;
    end if;


    total_error := error_count1 + error_count2;

    if (total_error = 0) then
        report "All TEST passed!" severity note;
    else
            
            report "SIMULATION FINISHED WITH " &
                   integer'image(total_error) & " ERROR(S)"
                   severity failure;
    end if;

    report "End of simulation" severity note;
    wait;


    end process STIM;


































end architecture sim;










