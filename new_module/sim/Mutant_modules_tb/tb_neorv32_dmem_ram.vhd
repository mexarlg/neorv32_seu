--==============================================================================
--  Testbench   : NEORV32 DMEM SEU / MBU Fault Injection Testbench
--  File        : tb_neorv32_dmem_ram.vhd
--
--  Description :
--      Verification environment for the NEORV32 DMEM fault injection system.
--
--      This testbench validates the behavior of the modified DMEM wrapper and
--      associated SPRAM primitives implementing:
--
--          - Single Event Upset (SEU) injection
--          - Multiple Bit Upset (MBU) injection
--          - Random fault address generation using LFSR
--          - Random fault trigger generation
--          - Bit-flip mask generation
--          - Fault reporting outputs
--
--      The DUT injects persistent memory corruptions directly into the RAM
--      array by XOR-applying a fault mask on a selected memory word.
--
--      Fault injection is controlled through:
--
--          fault_enable   : global fault injection enable
--          fault_trigger  : inject fault on current cycle
--          fault_MBU      : select SEU or MBU mode
--          mask           : custom MBU corruption mask
--
--
--  Injection Model :
--
--      SEU mode:
--          - A pseudo-random bit position is selected
--          - A single bit is flipped inside the targeted memory word
--
--      MBU mode:
--          - A user-defined corruption mask is applied
--          - Multiple adjacent or arbitrary bits may be flipped
--
--
--  Verified Features :
--
--      TEST 1:
--          Verifies outputs remain zero when:
--              - en_i            = '0'
--              - fault_enable    = '0'
--              - fault_trigger   = '0'
--
--      TEST 2:
--          Verifies no fault injection occurs when:
--              - fault_enable    = '0'
--              - en_i            = '1'
--
--      TEST 3:
--          Verifies no fault injection occurs when:
--              - fault_enable    = '1'
--              - fault_trigger   = '0'
--
--      TEST 4:
--          Verifies correct SEU injection behavior:
--              - single bit flip
--              - correct bit position reporting
--              - correct corrupted data generation
--
--      TEST 5:
--          Verifies correct MBU injection behavior:
--              - multi-bit corruption
--              - correct mask application
--              - correct corrupted data generation
--
--
--  Methodology :
--
--      - Pseudo-random stimuli are generated using a maximal-length LFSR
--      - Fault events are injected probabilistically
--      - Corrupted data is reconstructed and verified cycle-by-cycle
--      - Automatic self-checking assertions detect mismatches
--
--
--  Notes :
--
--      - Fault injections are persistent:
--            injected corruptions modify the actual RAM content
--
--      - Simultaneous user write and fault injection accesses are allowed
--        and intentionally left unresolved to emulate realistic hardware
--        collision scenarios
--
--      - This testbench targets functional validation rather than timing
--        closure or synthesis verification
--
--
--  Author      : Olivier Oribes
--  Project     : NEORV32_SEU
--  Language    : VHDL-2008
--
--  Created     : 28/04/2026
--  Last update : 10/05/2026
--  Version     : 2.0
--
--
--  Dependencies :
--      - neorv32_dmem_ram.vhd
--      - neorv32_prim_spram.vhd
--      - seu_pkg.vhd
--
--
--  License :
--      MIT License
--
--==============================================================================
library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.seu_pkg.all;


entity tb_neorv32_dmem_ram is 
end tb_neorv32_dmem_ram;


architecture sim of tb_neorv32_dmem_ram is

    constant AWIDTH : natural := 12;
    constant OUTREG : natural := 1;
    constant CLK_PERIOD : time := 10 ns;
    constant ZERO       : std_ulogic_vector(31 downto 0) := (others => '0');
    signal clk_i  : std_ulogic := '0';                      -- clock, rising-edge
    signal en_i   : std_ulogic_vector(3 downto 0);   -- byte-wise access-enable
    signal rw_i   : std_ulogic;                      -- 0=read, 1=write
    signal addr_i : std_ulogic_vector(31 downto 0);  -- full byte address
    signal data_i : std_ulogic_vector(31 downto 0);  -- write data
    signal data_o : std_ulogic_vector(31 downto 0);  -- read data, sync

    -- SEU injection fault setting ----------------------------------
    signal rst_n           :  std_ulogic;
    signal fault_enable    :  std_ulogic;
    signal fault_trigger   :  std_ulogic;
    signal faulted_bit     :  std_ulogic_vector(31 downto 0);
    signal at_bit          :  std_ulogic_vector(4 downto 0);
    signal faulted_address :  std_ulogic_vector(31 downto 0);
    signal clean_data      :  std_ulogic_vector(31 downto 0);
    signal faulted_data    :  std_ulogic_vector(31 downto 0);

    -- MBU injection fault setting ----------------------------------
    signal fault_MBU       :  std_ulogic := '0';
    signal mask            :  std_ulogic_vector(31 downto 0) := (others => '0');

begin
    -- ------------------------------------------------------------------
    -- DUT
    -- ------------------------------------------------------------------

    DUT : entity work.neorv32_dmem_ram  
        generic map(
            AWIDTH => AWIDTH,
            OUTREG => OUTREG
        )
        port map(
            clk_i   => clk_i,
            en_i    => en_i,
            rw_i    => rw_i,
            addr_i  => addr_i,
            data_i  => data_i,
            data_o  => data_o,

            -- SEU injection fault setting ---------------
            rst_n           => rst_n,
            fault_enable    => fault_enable,
            fault_trigger   => fault_trigger,
            faulted_address => faulted_address,
            at_bit          => at_bit,
            clean_data      => clean_data,
            faulted_data    => faulted_data,

            -- MBU injection fault setting ---------------------------------
            fault_MBU       => fault_MBU,
            mask            => mask
        );

    
    -- ------------------------------------------------------------------
    -- Clock generation : 100 MHz
    -- ------------------------------------------------------------------
    clk_i <= not(clk_i) after CLK_PERIOD/2;


    -- ------------------------------------------------------------------
    -- Stimulus
    -- ------------------------------------------------------------------

    SIM : process

        constant N             : natural := 1000;
        variable total_error   : natural := 0;
        variable error_count1  : natural := 0;
        variable error_count2  : natural := 0;
        variable error_count3  : natural := 0;
        variable error_count4  : natural := 0;
        variable error_count5  : natural := 0;
        variable randvect      : std_ulogic_vector(31 downto 0) := x"A5C3F19B";
        variable data_fault    : std_ulogic_vector(31 downto 0);
        variable bitpos        : natural range 0 to 31;
        variable fault_mask    : std_ulogic_vector(31 downto 0); 
        variable expected_mask : std_ulogic_vector(31 downto 0); 

    begin


        -- ----------------------------------------------------------------
        -- Init
        -- ----------------------------------------------------------------
        fault_enable   <= '0';
        fault_trigger  <= '0';
        fault_MBU      <= '0';
        mask           <= (others => '0');

        -- ================================================================
        -- RAM initialization
        -- ================================================================

        en_i <= "1111";
        rw_i <= '1';

        for i in 0 to (2**(AWIDTH-2))-1 loop   -- covers all 1024 entries

            addr_i <= std_ulogic_vector(to_unsigned(i*4, 32));
            data_i <= std_ulogic_vector(to_unsigned(i, 32));

            wait until rising_edge(clk_i);
            wait until rising_edge(clk_i);

        end loop;

        rw_i <= '0';

        wait until rising_edge(clk_i);
        wait until rising_edge(clk_i);
        
        -- ================================================================
        -- TEST 1 : fault_enable and fault_trigger = '0'
        -- ================================================================

        for i in 1 to N loop

            wait until rising_edge(clk_i);
            
            if (clean_data /= ZERO) then
            
                report "ERROR clean_data value : " & LF &
                       "Equal to   : " & to_hstring(clean_data) & LF &
                       "Expected value : " & to_hstring(ZERO) & LF
                        severity error;
                        error_count1 := error_count1 + 1;
            
            elsif (faulted_data /= ZERO) then

                report "ERROR faulted_data value : " & LF &
                       "Equal to   : " & to_hstring(faulted_data) & LF &
                       "Expected value : " & to_hstring(ZERO) & LF
                        severity error;
                        error_count1 := error_count1 + 1;
            end if;

        end loop;


        if (error_count1 = 0) then
            report "All TEST 1 passed." severity note;
        end if;

        -- ================================================================
        -- TEST 2 : fault_enable = '0' 
        -- ================================================================
        
        fault_enable  <= '0';
        fault_trigger <= '1';

        wait until rising_edge(clk_i);
        wait for 1 ns;  

        for i in 1 to N loop

            wait until rising_edge(clk_i);

            if (clean_data /= ZERO) then
            
                report "ERROR clean_data value : " & LF &
                       "Equal to   : " & to_hstring(clean_data) & LF &
                       "Expected value : " & to_hstring(ZERO) & LF
                        severity error;
                        error_count2 := error_count2 + 1;
            
            elsif (faulted_data /= ZERO) then

                report "ERROR faulted_data value : " & LF &
                       "Equal to   : " & to_hstring(faulted_data) & LF &
                       "Expected value : " & to_hstring(ZERO) & LF
                        severity error;
                        error_count2 := error_count2 + 1;
            end if;

        end loop;


        if (error_count2 = 0) then
            report "All TEST 2 passed." severity note;
        end if;

        
        -- ================================================================
        -- TEST 3 : fault_trigger = '0'
        -- ================================================================
        
        fault_enable  <= '1';
        fault_trigger <= '0';

        wait until rising_edge(clk_i);
        wait for 1 ns;  

        for i in 1 to N loop

            wait until rising_edge(clk_i);

            if (clean_data /= ZERO) then
            
                report "ERROR clean_data value : " & LF &
                       "Equal to   : " & to_hstring(clean_data) & LF &
                       "Expected value : " & to_hstring(ZERO) & LF
                        severity error;
                        error_count3 := error_count3 + 1;
            
            elsif (faulted_data /= ZERO) then

                report "ERROR faulted_data value : " & LF &
                       "Equal to   : " & to_hstring(faulted_data) & LF &
                       "Expected value : " & to_hstring(ZERO) & LF
                        severity error;
                        error_count3 := error_count3 + 1;
            end if;

        end loop;


        if (error_count3 = 0) then
            report "All TEST 3 passed." severity note;
        end if;

        
        -- ================================================================
        -- TEST 4 : Injection SEU into RAM
        -- ================================================================
    
        fault_enable  <= '1';

        wait until rising_edge(clk_i);  
        wait for 1 ns;

        for i in 1 to N loop

            randvect := fibo_lfsr(randvect);

            fault_trigger <= randvect(0);

            wait until rising_edge(clk_i);
            wait for 1 ns;

            if (fault_trigger = '0') then

                if (clean_data /= ZERO) then
                
                    report "ERROR clean_data value : " & LF &
                        "Equal to   : " & to_hstring(clean_data) & LF &
                        "Expected value : " & to_hstring(ZERO) & LF 
                            severity error;
                            error_count4 := error_count4 + 1;
                
                elsif (faulted_data /= ZERO) then

                    report "ERROR faulted_data value : " & LF &
                        "Equal to   : " & to_hstring(faulted_data) & LF &
                        "Expected value : " & to_hstring(ZERO) & LF
                            severity error;
                            error_count4 := error_count4 + 1;
                end if;
            

            else 
                
                data_fault := clean_data;
                data_fault(to_integer(unsigned(at_bit))) := not data_fault(to_integer(unsigned(at_bit)));

                expected_mask := (others => '0');
                expected_mask(to_integer(unsigned(at_bit))) := '1';

                if ((clean_data xor faulted_data) /= expected_mask) then
                
                    report  "ERROR clean_data shouldn't be equal to faulted_data : " & LF &
                            "Clean data equal to : " & to_hstring(clean_data) & LF &
                            "Faulted data equal to : " & to_hstring(faulted_data) & LF &
                            "but should equal to : " & to_hstring(data_fault) & LF &
                            "Fault mask equal to " & to_string(expected_mask)
                            severity failure;
                            error_count4 := error_count4 + 1;
                end if;
                
            
            end if;
        end loop;


        if (error_count4 = 0) then
            report "All TEST 4 passed." severity note;

        else 
            report "Failure" severity failure;
            wait;
        end if;
        


        -- ================================================================
        -- TEST 5 : Injection MBU into RAM
        -- ================================================================
        
        fault_enable  <= '1';
        fault_MBU     <= '1';

        wait until rising_edge(clk_i);
        wait for 1 ns;

        for i in 1 to N loop

            fault_mask := (others => '0');
            randvect := fibo_lfsr(randvect);

            fault_trigger <= randvect(0);
            
            bitpos := to_integer(unsigned(randvect(4 downto 0)));

            if (bitpos = 0) then

                fault_mask(0) := '1';
                fault_mask(1) := '1';
                fault_mask(2) := '1';

            elsif (bitpos = 31) then

                fault_mask(29) := '1';
                fault_mask(30) := '1';
                fault_mask(31) := '1';

            else

                fault_mask(bitpos-1) := '1';
                fault_mask(bitpos)   := '1';
                fault_mask(bitpos+1) := '1';

            end if;
                        
            mask <= fault_mask;

            wait until rising_edge(clk_i);
            wait for 1 ns;
            
            if (fault_trigger = '0') then

                if (clean_data /= ZERO) then
                
                    report "ERROR clean_data value : " & LF &
                        "Equal to   : " & to_hstring(clean_data) & LF &
                        "Expected value : " & to_hstring(ZERO) & LF
                            severity error;
                            error_count5 := error_count5 + 1;
                
                elsif (faulted_data /= ZERO) then

                    report "ERROR faulted_data value : " & LF &
                        "Equal to   : " & to_hstring(faulted_data) & LF &
                        "Expected value : " & to_hstring(ZERO) & LF
                            severity error;
                            error_count5 := error_count5 + 1;
                end if;
            

            else 
                
                data_fault := clean_data xor fault_mask;
                
                if (faulted_data /= data_fault) then
                
                    report "ERROR clean_data shouldn't be equal to faulted_data : " & LF &
                            "Faulted data equal to : " &to_hstring(faulted_data) & LF &
                            "but should equal to : " & to_hstring(data_fault) & LF &
                            "The mask value is " & to_hstring(fault_mask) 
                            severity error;
                            error_count5 := error_count5 + 1;
                end if;
            
            end if;
        end loop;


        if (error_count5 = 0) then
            report "All TEST 5 passed." severity note;
        else 
            report "Failure" severity failure;
        end if;
        

        -- =========================================================================
        -- TEST RST_N : synchronous active-low reset
        -- -------------------------------------------------------------------------
        -- Verifies that after reset:
        --   - randvect is restored to seed x"A5C3F19B"
        --   - at_bit is cleared to 0
        -- Since randvect is internal, we observe its effect indirectly:
        --   two consecutive injections after reset must produce the same
        --   faulted_address and at_bit as two fresh injections from the seed.
        -- =========================================================================
        --report "Starting TEST RST_N..." severity note;



        total_error := error_count1 + error_count2 + error_count3 + error_count4 + error_count5;

        -- ================================================================
        -- End of simulation
        -- ================================================================
        if ( total_error = 0) then
            report "ALL TESTS PASSED" severity note;
        else
            
            report "SIMULATION FINISHED WITH " &
                   integer'image(total_error) & " ERROR(S)"
                   severity failure;
        end if;

        report "End of simulation" severity failure;

    end process SIM;
    
end sim;    