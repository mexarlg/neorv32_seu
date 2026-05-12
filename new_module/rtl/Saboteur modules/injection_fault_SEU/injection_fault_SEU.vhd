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
--  Last update : 01/05/2026
--
--  Version     : 1.1
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
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity injection_fault_SEU is 
    generic(
        DATA_LENGTH    : positive;
        ADDRESS_LENGTH : positive;
        MEMORY_DEPTH   : positive
    );
    port(
        clk          : in  std_ulogic;
        fault_enable : in  std_ulogic;

        -- interface RAM
        en_o   : out std_ulogic;
        rw_o   : out std_ulogic;
        addr_o : out std_ulogic_vector(ADDRESS_LENGTH-1 downto 0);
        data_o : out std_ulogic_vector(DATA_LENGTH-1 downto 0);
        data_i : in  std_ulogic_vector(DATA_LENGTH-1 downto 0)
    );

end entity injection_fault_SEU;


architecture rtl of injection_fault_SEU is

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

    constant seed   : std_ulogic_vector(31 downto 0) := x"A5C3F19B";
    type state_t is (IDLE, READ, MODIFY, WRITE);
    signal state          : state_t := IDLE;
    signal rand_vect      : std_ulogic_vector(31 downto 0) := fibo_lfsr(seed);
    signal data_faulted_s : std_ulogic_vector(DATA_LENGTH-1 downto 0);
    signal addr_s         : std_ulogic_vector(ADDRESS_LENGTH-1 downto 0);

begin

    proc_fault_injection: process(clk)

        variable fault_mask          : std_ulogic_vector(DATA_LENGTH - 1 downto 0);
        variable stuckatbit          : natural range 0 to DATA_LENGTH - 1;



    begin

        if rising_edge(clk) then
            
            rand_vect <= fibo_lfsr(rand_vect);

            case state is

                when IDLE =>

                    en_o <= '0';
                    rw_o <= '0';

                    if fault_enable = '1' then

                        en_o <= '1';
                        state <= READ;

                    end if;

                when READ =>

                    rw_o <= '0';

                    addr_s <= std_ulogic_vector(
                        to_unsigned(
                            to_integer(unsigned(rand_vect(5 downto 0))) mod MEMORY_DEPTH,
                            ADDRESS_LENGTH
                        )
                    );

                    addr_o <= addr_s;

                    state <= MODIFY;

                when MODIFY =>

                    -- generate the index of the bitflip
                    stuckatbit := to_integer(unsigned(rand_vect(7 downto 0))) mod DATA_LENGTH;

                    fault_mask := (others => '0');
                    fault_mask(stuckatbit) := '1';
                    
                    
                    data_faulted_s <= data_i xor fault_mask;

                    state <= WRITE;

                when WRITE =>

                    en_o   <= '1';
                    rw_o   <= '1';
                    addr_o <= addr_s;
                    data_o <= data_faulted_s;

                    state <= IDLE;

                when others =>
                    state <= IDLE;

            end case;
        
           
        end if;
    end process proc_fault_injection;



end architecture rtl;