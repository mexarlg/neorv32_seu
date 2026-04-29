-- ==============================================================================
--  Testbench   : Fault Injection Top Module
--  File        : tb_fault_injection_top.vhd
--
--  Description :
--      This testbench verifies the functional correctness and statistical
--      behavior of the fault_injection_top module.
--
--      The DUT combines:
--          - A probabilistic fault injection controller (LFSR-based)
--          - A combinational fault injection block
--
--      The system supports:
--          - Transient faults (SET - Single Event Transient)
--          - Permanent stuck-at faults
--
--      Three main test scenarios are covered:
--
--      TEST 1 – Fault disable behavior:
--          Ensures that when fault_enable = '0', the output data strictly
--          matches the input data, regardless of control signals.
--
--      TEST 2 – Transient fault injection:
--          - Verifies deterministic behavior at 100% injection rate
--            (nbr_bits_to_match = 0)
--          - Validates probabilistic fault injection for varying rates:
--                P(fault) = 1 / 2^N
--            using statistical estimation over large sample sizes
--          - Confirms that observed fault rates match expected probabilities
--            within a configurable tolerance (EPSILON)
--
--      TEST 3 – Permanent fault injection:
--          Ensures correct stuck-at behavior by forcing a selected bit
--          to a constant value across multiple input patterns
--
--  Methodology:
--      - Pseudo-random stimulus generated via a 32-bit LFSR
--      - Bit-level fault targeting using dynamic masks
--      - Statistical validation of injection rates
--      - Detailed error reporting with mismatch localization
--
--  Notes:
--      - The probabilistic test requires large iteration counts (up to 10M)
--        to achieve stable estimation for low probabilities
--      - Relative error is used to evaluate statistical accuracy
--
--  Author      : Olivier Oribes
--  Created     : 28/04/2026
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
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_fault_injection_top is
end entity tb_fault_injection_top;


architecture sim of tb_fault_injection_top is

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

    -- ------------------------------------------------------------------
    -- Constants / signals
    -- ------------------------------------------------------------------
    constant CLK_PERIOD      : time := 10 ns;   -- 100 MHz 
    constant DATA_LENGTH     : positive := 32;
    signal fault_enable      : std_ulogic;
    signal clk               : std_ulogic := '0';
    signal rst_n             : std_ulogic;
    signal data_in           : std_ulogic_vector(DATA_LENGTH-1 downto 0);
    signal data_out          : std_ulogic_vector(DATA_LENGTH-1 downto 0);
    signal transient_fault   : std_ulogic;
    signal permanent_fault   : std_ulogic;
    signal nbr_bits_to_match : natural range 0 to 15;
    signal stuckatbit        : natural range 0 to DATA_LENGTH-1;
    signal stuckatvalue      : std_ulogic;
    signal fault_mask        : std_ulogic_vector(DATA_LENGTH-1 downto 0);

begin

    
    DUT : entity work.fault_injection_top 
        generic map(
            DATA_LENGTH        =>  DATA_LENGTH
        )
        port map(
            data_in            => data_in,
            data_out           => data_out,
            fault_enable       => fault_enable,
            transient_fault    => transient_fault,
            permanent_fault    => permanent_fault,
            stuckatbit         => stuckatbit,
            stuckatvalue       => stuckatvalue,
            fault_mask         => fault_mask,
            clk                => clk,
            rst_n              => rst_n,
            nbr_bits_to_match  => nbr_bits_to_match
        );

    -- ------------------------------------------------------------------
    -- Clock generation : 100 MHz
    -- ------------------------------------------------------------------
    clk <= not(clk) after CLK_PERIOD/2;

    -- ------------------------------------------------------------------
    -- Stimulus
    -- ------------------------------------------------------------------

    SIM : process

        constant N                 : natural := 1000;
        constant seed              : std_ulogic_vector(31 downto 0) := x"A5C3F19B";
        constant EPSILON           : real    := 0.1;
        variable K                 : natural;
        variable rand_vect         : std_ulogic_vector(31 downto 0);               -- The bitstream generated using the seed
        variable error_count1      : natural := 0;
        variable error_count2      : natural := 0;
        variable error_count3      : natural := 0;        
        variable total_error       : natural := 0;
        variable expected_result   : std_ulogic_vector(DATA_LENGTH-1 downto 0);   
        variable rand_data         : std_ulogic_vector(DATA_LENGTH-1 downto 0);    -- Bit targeted for Single Event Transient
        variable mask              : std_ulogic_vector(DATA_LENGTH-1 downto 0) := (others => '0');
        variable stucked_bit       : natural range 0 to DATA_LENGTH - 1;
        variable stucked_value     : std_ulogic;
        variable perm_val          : std_ulogic;
        variable trans_val         : std_ulogic;
        variable nbr_bit           : natural range 0 to 15;
        variable rate              : real;
        variable expected_rate     : real;
        variable diff              : real;
        variable count_matched     : natural;


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
        permanent_fault       <= '0';
        fault_mask            <= (others => '0');
        rst_n                 <= '0';
        
        wait until rising_edge(clk);

        
        rst_n <= '1';


        wait until rising_edge(clk);


        -- ================================================================
        -- TEST 1 : Fault enable
        -- ================================================================

        error_count1   := 0;
        rand_vect := seed;

        for i in 0 to N loop

            rand_vect := fibo_lfsr(rand_vect);
            perm_val  := rand_vect(0);
            trans_val := rand_vect(31);

            transient_fault <= trans_val;
            permanent_fault <= perm_val;

            rand_data := rand_vect(31 downto (32 - DATA_LENGTH));
            data_in <= rand_data;

            wait until rising_edge(clk);

            if (data_in /= data_out) then

                report "ERROR TEST 1 data_out = 0x" & to_hstring(data_out) &
                    " but expected = 0x" & to_hstring(data_in)
                    severity error;

                error_count1 := error_count1 + 1;

            end if;
        
        end loop;
        
        if (error_count1 = 0) then
            report "All TEST 1 passed." severity note;
        end if;

        -- ================================================================
        -- TEST 2 : Transient fault injection
        -- ================================================================
        
    
        -- -- ================================================================
        -- -- 100 % injection fault
        -- -- ================================================================

        rand_vect       := seed;
        error_count2     := 0;
        nbr_bits_to_match <= 0;
        
        wait until rising_edge(clk);

        for i in 0 to N loop    

            next_rand(rand_vect);

            -- Generate a random bit index within [0, DATA_LENGTH-1]
            stucked_bit := to_integer(unsigned(rand_vect(7 downto 0))) mod DATA_LENGTH;


            -- Activation of the fault injection for SET
            fault_enable    <= '1';
            transient_fault <= '1';
            permanent_fault <= '0';


            -- The mask used to target bitflip

            mask               := (others => '0');
            mask(stucked_bit)  := '1';
            fault_mask <= mask;

            wait until rising_edge(clk);

            
            rand_data           := rand_vect(31 downto (32 - DATA_LENGTH));
            expected_result     := rand_data xor mask;


            data_in <= rand_data;


            wait until rising_edge(clk);


            if (data_out /= expected_result) then

                report "ERROR TEST 2 data_out = 0x" & to_hstring(data_out) &
                " but expected = 0x" & to_hstring(expected_result)
                severity error;


                for j in 0 to (DATA_LENGTH-1) loop

                    if ((data_out(j) xor expected_result(j)) = '1') then
                        
                        report "ERROR: Bit mismatch" & LF &
                        "Detected bit  : " & integer'image(j) & LF &
                        "Expected bit  : " & integer'image(stucked_bit)
                        severity error;

                    end if;

                end loop;

                error_count2 := error_count2 + 1;

            end if;
            
            mask        := (others => '0'); -- Reset of the fault mask
            fault_mask  <= mask;
            
        end loop;
        

        if (error_count2 = 0) then
            report "TEST 100 % injection fault passed." severity note;
        end if;


        -- -- ================================================================
        -- -- ??? % injection fault
        -- -- ================================================================
        
        -- Enable transient fault injection (SET mode only)
        fault_enable    <= '1';
        transient_fault <= '1';
        permanent_fault <= '0';

        -- Initialize random generator
        rand_vect := seed;

        for j in 1 to 8 loop

            -- Configure number of bits used for LFSR comparison
            -- This directly controls the expected fault probability
            nbr_bit := j;
            nbr_bits_to_match <= nbr_bit;

            count_matched := 0;

            -- Number of samples used for statistical estimation
            -- Increased for low probabilities to improve accuracy
            K := 1_000_000;
            if (j = 8) then
                K := 10_000_000;
            end if;

            wait until rising_edge(clk);

            for i in 1 to K loop

                -- Generate random bit to flip
                next_rand(rand_vect);
                stucked_bit := to_integer(unsigned(rand_vect(7 downto 0))) mod DATA_LENGTH;

                -- Apply single-bit fault mask
                mask              := (others => '0');
                mask(stucked_bit) := '1';
                fault_mask        <= mask;

                wait until rising_edge(clk);

                -- Apply random input data
                next_rand(rand_vect);
                rand_data := rand_vect(31 downto (32 - DATA_LENGTH));
                data_in   <= rand_data;

                wait until rising_edge(clk);

                -- Detect if a fault has been injected (bit flip occurred)
                if (data_out /= rand_data) then
                    count_matched := count_matched + 1;
                end if;

                -- Reset mask after each cycle
                mask       := (others => '0');
                fault_mask <= mask;

                wait until rising_edge(clk);

            end loop;

            -- Expected probability of fault injection
            expected_rate := 1.0 / real(2**nbr_bit);

            -- Measured probability
            rate := real(count_matched) / real(K);

            -- Relative error between expected and observed values
            diff := abs(rate - expected_rate) / rate;

            -- Check if error is within acceptable tolerance
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

                error_count2 := error_count2 + 1;
            end if;

        end loop;

        -- Report global result of probabilistic test
        if (error_count2 = 0) then
            report "All TEST 2 passed." severity note;
        end if;

        -- Disable fault injection after test
        fault_enable    <= '0';
        transient_fault <= '0';
        mask       := (others => '0');
        fault_mask <= mask;

        wait until rising_edge(clk);
                    
        -- ================================================================
        -- TEST 3 : Permanent fault injection
        -- ================================================================

        rand_vect   := seed;
        error_count3 := 0;
        
        for i in 0 to N loop

            next_rand(rand_vect);

            -- Generate a random bit index within [0, DATA_LENGTH-1]
            stucked_bit  := to_integer(unsigned(rand_vect(7 downto 0))) mod DATA_LENGTH;
            stuckatbit   <= stucked_bit;
            -- Generate a random value within [0, 1}
            stucked_value := rand_vect(0);
            stuckatvalue  <= stucked_value;


            -- Enable permanent fault injection
            fault_enable    <= '1';
            transient_fault <= '0';
            permanent_fault <= '1';

        
            wait until rising_edge(clk);

            ----------------------------------------------------------------
            -- Apply multiple input values to verify persistence of the fault
            ----------------------------------------------------------------
            for k in 0 to 3 loop  -- Test several random inputs

                next_rand(rand_vect);

                -- Extract random data of DATA_LENGTH bits
                rand_data := rand_vect(31 downto (32 - DATA_LENGTH));

                -- Expected output: selected bit forced to stucked_value
                expected_result              := rand_data;
                expected_result(stucked_bit) := stucked_value;

                data_in <= rand_data;

                wait until rising_edge(clk);

                -- Check output correctness under permanent fault condition
                if (data_out /= expected_result) then

                    report "ERROR TEST 3 data_out = 0x" & to_hstring(data_out) &
                        " but expected = 0x" & to_hstring(expected_result)
                        severity error;

                    if (data_out(stucked_bit) /= expected_result(stucked_bit)) then

                        report "ERROR: Bit mismatch at position : " & integer'image(stucked_bit) & LF &
                        "Input bit     : " & std_ulogic'image(rand_data(stucked_bit)) & LF &
                        "Detected bit  : " & std_ulogic'image(data_out(stucked_bit)) & LF &
                        "Expected bit  : " & std_ulogic'image(stucked_value)
                        severity error;
                    
                    end if;

                    -- Identify which bit differs
                    for j in 0 to DATA_LENGTH-1 loop
                        if ((data_out(j) xor expected_result(j)) = '1') then
                            report "ERROR: Bit mismatch" & LF &
                                "Detected bit  : " & integer'image(j) & LF &
                                "Expected bit  : " & integer'image(j)
                                severity error;
                        end if;
                    end loop;

                    error_count3 := error_count3 + 1;

                end if;

            end loop;

            ----------------------------------------------------------------
            -- Disable fault after validation
            ----------------------------------------------------------------
            permanent_fault <= '0';
            fault_enable    <= '0';
            fault_mask      <= (others => '0');

            wait until rising_edge(clk);

        end loop;

        if (error_count3 = 0) then
            report "All TEST 3 passed." severity note;
        end if;
        
        total_error := error_count1 + error_count2 + error_count3;
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
        finish;

    end process SIM;


end architecture sim;

