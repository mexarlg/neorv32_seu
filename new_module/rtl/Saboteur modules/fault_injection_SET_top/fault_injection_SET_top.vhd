-- ==============================================================================
--  Module      : Fault Injection Top
--  File        : fault_injection_top.vhd
--
--  Description :
--      Top-level integration module for fault injection mechanisms.
--
--      This module connects:
--          - fault_injection_controller :
--                Generates a probabilistic trigger signal (match)
--                based on an internal LFSR and a configurable threshold
--
--          - injection_fault :
--                Applies faults to the input data according to control signals
--
--      Architecture principle:
--          - The controller defines WHEN a transient fault occurs
--          - The injection block defines HOW the fault is applied
--
--      Supported fault models:
--          - Transient faults (SET – Single Event Transient)
--                Triggered probabilistically using match signal
--                Bits flipped according to fault_mask
--
--          - Permanent faults (stuck-at)
--                Forces a selected bit to a constant value
--
--      Fault priority:
--          permanent_fault > transient_fault > normal operation
--
--  Generics:
--      DATA_LENGTH :
--          Width of the input/output data bus (must be > 0)
--
--  Ports:
--      clk               : input  - System clock
--      rst_n             : input  - Asynchronous active-low reset
--
--      data_in           : input  - Input data bus
--      data_out          : output - Output data (possibly faulted)
--
--      fault_enable      : input  - Global enable for fault injection system
--      transient_fault   : input  - Enables transient fault mechanism (SET)
--      permanent_fault   : input  - Enables stuck-at fault mechanism
--
--      nbr_bits_to_match : input  - Controls injection probability:
--                                   P(fault) = 1 / 2^nbr_bits_to_match
--
--      stuckatbit        : input  - Index of affected bit (permanent fault)
--      stuckatvalue      : input  - Forced value ('0' or '1')
--
--      fault_mask        : input  - Bit mask for transient faults (1 = flip)
--
--  Notes:
--      - The module is synchronous (controller) + combinational (injection)
--      - No internal storage of faults (purely driven by inputs)
--      - Designed for SEU/SET fault injection campaigns
--
--  Author      : Olivier Oribes
--  Created     : 29/04/2026
--  Last update : 30/04/2026
--
--  Version     : 1.1
--
--  Project     : Neorv32_SEU
--  Language    : VHDL
--
--  License     : MIT
-- ==============================================================================


library ieee;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity fault_injection_top is
    generic(
        DATA_LENGTH       : positive
    );
    port(
        clk               : in  std_ulogic;
        rst_n             : in  std_ulogic;

        data_in           : in  std_ulogic_vector(DATA_LENGTH-1 downto 0);
        data_out          : out std_ulogic_vector(DATA_LENGTH-1 downto 0);

        fault_enable      : in  std_ulogic;
        transient_fault   : in  std_ulogic;
        permanent_fault   : in  std_ulogic;

        nbr_bits_to_match : in  natural range 0 to 15;

        stuckatbit        : in  natural range 0 to DATA_LENGTH-1;
        stuckatvalue      : in  std_ulogic;
        fault_mask        : in  std_ulogic_vector(DATA_LENGTH-1 downto 0)
    );

end entity fault_injection_top;


architecture rtl of fault_injection_top is


    signal match_sig : std_ulogic;

begin

    -- controller

    controller_inst : entity work.fault_injection_controller 
        port map(
            fault_enable       => fault_enable,
            clk                => clk,
            rst_n              => rst_n,
            nbr_bits_to_match  => nbr_bits_to_match,
            match              => match_sig
        );



    -- Injection block
    injection_inst : entity work.injection_fault
        generic map(
            DATA_LENGTH => DATA_LENGTH
        )
        port map(
            data_in         => data_in,
            data_out        => data_out,
            fault_enable    => fault_enable,
            transient_fault => transient_fault,
            permanent_fault => permanent_fault,
            stuckatbit      => stuckatbit,
            stuckatvalue    => stuckatvalue,
            fault_mask      => fault_mask,
            match           => match_sig
        );

end architecture rtl;

