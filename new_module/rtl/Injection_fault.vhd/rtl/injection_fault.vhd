--==============================================================================
--  Module      : Injection Fault
--  File        : injection_fault.vhd
--
--  Description :
--      Combinational fault injection block used to simulate transient and
--      permanent Single Event Upsets (SEU) and Multiple Bit Upsets (MBU)
--      in a digital system.
--
--      This module modifies an input data bus by conditionally flipwping one
--      or multiple bits using a fault mask. It does not store any state:
--      faults are applied instantaneously based on input control signals.
--
--  Features:
--      - Probabilistic transient fault injection using external LFSR match signal
--      - Fine-grained control via enable, trigger, and match signals
--      - Persistent bit-flip fault affecting one or multiple bits
--      - Supports SEU (single-bit) and MBU (multi-bit) fault models
--      - Fully combinational (no clock, no internal state)
--
--  Behavior:
--      - Default behavior: data_out = data_in (no fault)
--      - Fault injection is enabled when:
--            fault_enable = '1'
--
--      - Persistent fault:
--            If permanent_fault = '1', selected bits are continuously flipped
--            according to fault_mask (models persistent SEU/MBU)
--
--      - Transient fault:
--            If transient_fault = '1' AND match = '1', selected bits are
--            flipped for the duration of the input pulse
--
--      - Priority:
--            permanent_fault > transient_fault > normal operation
--
--  Author      : Olivier Oribes
--  Created     : 26/04/2026
--  Last update : 26/04/2026
--
--  Version     : 1.0
--
--  Project     : CPU_Single_cycle
--  Language    : VHDL
--
--  Dependencies:
--      - External fault controller (LFSR + comparator generating 'match')
--
--  Generics:
--      DATA_LENGTH : Width of input/output data (must be > 0)
--
--  Ports:
--      data_in          : input  - Input data bus
--      fault_enable     : input  - Global enable for fault injection
--      transient_fault  : input  - Trigger signal for transient fault (pulse)
--      match            : input  - LFSR-based probabilistic trigger signal
--      permanent_fault  : input  - Enable persistent SEU/MBU fault
--      fault_mask       : input  - Bit mask defining flipped bits (1 = flip)
--      data_out         : output - Output data (possibly faulted)
--
--  License     : MIT
--==============================================================================


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity injection_fault is
    generic(
        DATA_LENGTH         : positive  -- Width of input/output data

    );
    port (
        data_in             : in  std_ulogic_vector(DATA_LENGTH-1 downto 0);

        fault_enable        : in  std_ulogic;  -- Global enable for fault injection (block activation)

        transient_fault     : in  std_ulogic;  -- Trigger signal to inject a transient fault
        match               : in  std_ulogic;  -- LFSR match signal (probabilistic fault trigger)
 
        permanent_fault     : in  std_ulogic;  -- Enable permanent stuck-at fault on selected bit
        fault_mask          : in  std_ulogic_vector(DATA_LENGTH-1 downto 0); -- Bit mask defining which bits are flipped (1 = flip, 0 = no effect)
        
        data_out            : out std_ulogic_vector(DATA_LENGTH-1 downto 0)  -- Output data (possibly faulted)
    );
end entity injection_fault;


architecture rtl of injection_fault is
begin

    fault_proc : process(all)
        variable data_fault : std_ulogic_vector(DATA_LENGTH-1 downto 0);

    begin

        -- Default behavior: no fault injection
        data_fault := data_in;

        -- Fault injection enabled
        if fault_enable = '1' then

            -- Permanent fault: always active when enabled
            if permanent_fault = '1' then

                -- Flip the selected bits (Single Event Upset - SEU or Multiple Even Upset - MBU)
                data_fault := data_fault xor fault_mask;

            -- Transient fault: occurs only when triggered and matched
            elsif (transient_fault = '1' and match = '1') then

                data_fault := data_fault xor fault_mask;

            end if;

        end if;

        -- Assign final output
        data_out <= data_fault;

    end process fault_proc;

end architecture rtl;