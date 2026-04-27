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
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;


entity tb_injection_fault is
end entity tb_injection_fault;


architecture sim of tb_injection_fault is

    -- ------------------------------------------------------------------
    -- pseudo_rand : simple LFSR-based 16-bit pseudo-random generator
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

    -- ------------------------------------------------------------------
    -- Constants / signals
    -- ------------------------------------------------------------------
    constant DATA_LENGTH        : positive     := 32;
    constant CLK_PERIOD         : time         := 10 ns;
    constant N                  : positive     := 1000;
    signal data_in              : std_ulogic_vector(DATA_LENGTH-1 downto 0);
    signal data_out             : std_ulogic_vector(DATA_LENGTH-1 downto 0);
    signal fault_enable         : std_ulogic    := '0';
    signal transient_fault      : std_ulogic    := '0';
    signal match                : std_ulogic    := '0';
    signal permanent_fault      : std_ulogic    := '0';
    signal fault_mask           : std_ulogic_vector(DATA_LENGTH-1 downto 0) := (others => '0');

begin

    -- ------------------------------------------------------------------
    -- DUT
    -- ------------------------------------------------------------------
    DUT : entity work.injection_fault
        generic map(DATA_LENGTH => DATA_LENGTH)
        port map (

            data_in             => data_in,
            data_out            => data_out,
            fault_enable        => fault_enable,
            transient_fault     => transient_fault,
            match               => match,
            permanent_fault     => permanent_fault,
            fault_mask          => fault_mask
        );
    

    -- ------------------------------------------------------------------
    -- Stimulus
    -- ------------------------------------------------------------------

    SIM : process

        constant seed              : std_ulogic_vector(31 downto 0) := x"A5C3F19B";
        
        variable rand_vect         : std_ulogic_vector(31 downto 0);              -- The bitstream generated using the seed
        variable error_count1      : natural := 0;
        variable error_count2      : natural := 0;                                 -- Counter of error
        variable total_error       : natural := 0;
        variable expected_result   : std_ulogic_vector(DATA_LENGTH-1 downto 0);   
        variable rand_data         : std_ulogic_vector(DATA_LENGTH-1 downto 0);
        variable stuckatbit        : natural;                                     -- Bit targeted for Single Event Transient
        variable mask              : std_ulogic_vector(DATA_LENGTH-1 downto 0) := (others => '0');


        -- Advance LFSR and return next 16-bit value
        procedure next_rand(variable v : inout std_ulogic_vector(31 downto 0)) is
        begin 
            
            v := fibo_lfsr(v);
        end procedure;
        
    begin

        -- ----------------------------------------------------------------
        -- Init
        -- ----------------------------------------------------------------
        fault_enable          <= '0';
        transient_fault       <= '0';
        match                 <= '0';
        permanent_fault       <= '0';
        fault_mask            <= (others => '0');

        -- ================================================================
        -- TEST 1 : Transient fault injection
        -- ================================================================
        
        rand_vect       := seed;
        error_count1     := 0;

        for i in 0 to N loop

            next_rand(rand_vect);

            -- Generate a random bit index within [0, DATA_LENGTH-1]
            stuckatbit := to_integer(unsigned(rand_vect(7 downto 0))) mod DATA_LENGTH;


            -- Activation of the fault injection for SET
            fault_enable    <= '1';
            transient_fault <= '1';
            match           <= '1'; 
            permanent_fault <= '0';


            -- The mask used to target bitflip

            mask              := (others => '0');
            mask(stuckatbit)  := '1';
            fault_mask <= mask;

            wait for CLK_PERIOD;
            wait for CLK_PERIOD;

            
            rand_data           := rand_vect(31 downto (32 - DATA_LENGTH));
            expected_result     := rand_data xor mask;


            data_in <= rand_data;

            wait for CLK_PERIOD;
            wait for CLK_PERIOD;

            if (data_out /= expected_result) then

                report "ERROR TEST 1 data_in = 0x" & to_hstring(data_out) &
                       " but expected = 0x" & to_hstring(expected_result) severity error;


                for j in 0 to (DATA_LENGTH-1) loop

                    if ((data_out(j) xor expected_result(j)) = '1') then
                        
                        report "ERROR: Bit mismatch" & LF &
                        "Detected bit  : " & integer'image(j) & LF &
                        "Expected bit  : " & integer'image(stuckatbit)
                        severity error;

                    end if;

                end loop;

                error_count1 := error_count1 + 1;

            end if;
            
            mask        := (others => '0'); -- Reset of the fault mask
            fault_mask  <= mask;
            
        end loop;
        
        if (error_count1 = 0) then
            report "All TEST 1 passed." severity note;
        end if;

        -- Deactivation of the fault injection
        fault_enable    <= '0';
        transient_fault <= '0';
        match           <= '0';
        mask        := (others => '0'); -- Reset of the fault mask
        fault_mask  <= mask;
        
        wait for CLK_PERIOD;
        wait for CLK_PERIOD;
    


        -- ================================================================
        -- TEST 2 : Permanent fault injection
        -- ================================================================

        rand_vect   := seed;
        error_count2 := 0;

        for i in 0 to N loop

            next_rand(rand_vect);

            -- Generate a random bit index within [0, DATA_LENGTH-1]
            stuckatbit := to_integer(unsigned(rand_vect(7 downto 0))) mod DATA_LENGTH;

            -- Enable permanent fault injection
            fault_enable    <= '1';
            transient_fault <= '0';
            match           <= '0'; 
            permanent_fault <= '1';

            -- Create fault mask targeting a single bit (SEU)
            mask := (others => '0');
            mask(stuckatbit) := '1';
            fault_mask <= mask;

            wait for CLK_PERIOD;

            ----------------------------------------------------------------
            -- Apply multiple input values to verify persistence of the fault
            ----------------------------------------------------------------
            for k in 0 to 3 loop  -- Test several random inputs

                next_rand(rand_vect);

                -- Extract random data of DATA_LENGTH bits
                rand_data := rand_vect(31 downto (32 - DATA_LENGTH));

                -- Expected output: bit-flipped according to mask
                expected_result := rand_data xor mask;

                data_in <= rand_data;

                wait for CLK_PERIOD;

                -- Check output correctness under permanent fault condition
                if (data_out /= expected_result) then

                    report "ERROR TEST 2 data_out = 0x" & to_hstring(data_out) &
                        " but expected = 0x" & to_hstring(expected_result)
                        severity error;

                    -- Identify which bit differs
                    for j in 0 to DATA_LENGTH-1 loop
                        if ((data_out(j) xor expected_result(j)) = '1') then
                            report "ERROR: Bit mismatch" & LF &
                                "Detected bit  : " & integer'image(j) & LF &
                                "Expected bit  : " & integer'image(stuckatbit)
                                severity error;
                        end if;
                    end loop;

                    error_count2 := error_count2 + 1;

                end if;

            end loop;

            ----------------------------------------------------------------
            -- Disable fault after validation
            ----------------------------------------------------------------
            permanent_fault <= '0';
            fault_enable    <= '0';
            fault_mask      <= (others => '0');

            wait for CLK_PERIOD;

        end loop;

        if (error_count2 = 0) then
            report "All TEST 2 passed." severity note;
        end if;
        
        total_error := error_count1 + error_count2;
        -- ================================================================
        -- Fin de simulation
        -- ================================================================
        if ( total_error = 0) then
            report "ALL TESTS PASSED" severity note;
        else
            
            report "SIMULATION FINISHED WITH " &
                   integer'image(total_error) & " ERROR(S)"
                   severity failure;
        end if;

        report "End of simulation" severity note;
        wait;

    end process SIM;

end architecture sim;