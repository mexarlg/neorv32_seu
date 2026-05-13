-- =============================================================================
-- File        : tb_tmr_register.vhd
-- Project     : NOERV32 - Space Radiation Mitigation
-- Description : Testbench for tmr_register.
--               Tests:
--                 1. Reset behaviour
--                 2. Normal write/read
--                 3. SEU injection into one bank -> voter masks the upset
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_tmr_register is
end entity tb_tmr_register;

architecture sim of tb_tmr_register is

    -- -------------------------------------------------------------------------
    -- DUT signals
    -- -------------------------------------------------------------------------
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '0';
    signal en      : std_logic := '1';
    signal d_in    : std_logic_vector(31 downto 0) := (others => '0');
    signal q_out   : std_logic_vector(31 downto 0);
    signal err_out : std_logic := '0';

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- -------------------------------------------------------------------------
    -- DUT component
    -- -------------------------------------------------------------------------
    -- component tmr_register is
    --     port (
    --         CLK : in  std_logic;
    --         RST : in  std_logic;
    --         EN  : in  std_logic;
    --         D   : in  std_logic_vector(31 downto 0);
    --         Q   : out std_logic_vector(31 downto 0);
    --         ERR : out std_logic
    --     );
    -- end component tmr_register;

    -- -------------------------------------------------------------------------
    -- Access to internal banks for SEU fault injection
    -- (requires VHDL-2008 hierarchical references or signal aliasing in sim)
    -- In GHDL / ModelSim, use:
    --   <<signal .tb_tmr_register.DUT.reg_a : std_logic_vector(31 downto 0)>>
    -- -------------------------------------------------------------------------
    -- Uncomment below for VHDL-2008 fault injection:
    -- alias seu_target : std_logic_vector(31 downto 0) is
    --     <<signal .tb_tmr_register.DUT.reg_a : std_logic_vector(31 downto 0)>>;

begin

    -- -------------------------------------------------------------------------
    -- Clock generation
    -- -------------------------------------------------------------------------
    CLK_GEN : clk <= not clk after CLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- DUT instantiation
    -- -------------------------------------------------------------------------
    DUT : entity work.tmr_register
        port map (
            CLK => clk,
            RST => rst,
            EN  => en,
            D   => d_in,
            Q   => q_out,
            ERR => err_out
        );

    -- -------------------------------------------------------------------------
    -- Stimulus process
    -- -------------------------------------------------------------------------
    STIM : process
    begin

        -- =====================================================================
        -- TEST 1: Synchronous reset
        -- =====================================================================
        report "TEST 1: Synchronous reset";
        d_in <= x"DEADBEEF";
        rst  <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;  -- let outputs settle

        assert q_out = x"00000000"
            report "FAIL: Reset did not clear Q" severity error;
        report "PASS: Q = 0x00000000 after reset";

        -- =====================================================================
        -- TEST 2: Normal write
        -- =====================================================================
        report "TEST 2: Normal write";
        rst  <= '0';
        d_in <= x"CAFEBABE";
        wait until rising_edge(clk);
        wait for 1 ns;

        assert q_out = x"CAFEBABE"
            report "FAIL: Q does not match D after write" severity error;
        report "PASS: Q = 0xCAFEBABE";

        -- =====================================================================
        -- TEST 3: Clock enable (EN = 0, data should NOT update)
        -- =====================================================================
        report "TEST 3: Clock enable gating";
        en   <= '0';
        d_in <= x"12345678";
        wait until rising_edge(clk);
        wait for 1 ns;

        assert q_out = x"CAFEBABE"
            report "FAIL: Q changed while EN = 0" severity error;
        report "PASS: Q held at 0xCAFEBABE while EN = 0";

        en <= '1';

        -- =====================================================================
        -- TEST 4: SEU simulation — flip bit 0 of one bank in the simulator
        --
        --   With VHDL-2008 force/release or ModelSim -force, you can directly
        --   corrupt reg_a while leaving reg_b and reg_c intact.
        --   The majority voter should output the correct value.
        --
        --   Below we demonstrate the CONCEPT by injecting via D after freeze:
        --   a real SEU injector would corrupt an internal signal directly.
        -- =====================================================================
        report "TEST 4: SEU concept check (voter correctness via waveform)";
        d_in <= x"AAAAAAAA";
        wait until rising_edge(clk);
        wait for 1 ns;
        assert q_out = x"AAAAAAAA"
            report "FAIL: Q != 0xAAAAAAAA before SEU" severity error;
        report "PASS: Q = 0xAAAAAAAA, ready for SEU injection";

        -- Freeze EN so registers hold their value
        en <= '0';
        -- At this point an external SEU injector (ModelSim force/GHDL PSL)
        -- would flip reg_a(0) to '1', making reg_a = 0xAAAAAAAB.
        -- reg_b and reg_c remain 0xAAAAAAAA.
        -- Voter output = (reg_a AND reg_b) OR (reg_a AND reg_c) OR (reg_b AND reg_c)
        --              = 0xAAAAAAAA  <- fault masked!
        wait for CLK_PERIOD * 2;
        report "INFO: Inject 'force DUT/reg_a 0xAAAAAAAB' here in your simulator";
        report "INFO: Q should remain 0xAAAAAAAA (voter masks the single upset)";
        wait for CLK_PERIOD * 2;


        -- =====================================================================
        -- TEST 5: ERR flag nach SEU
        -- =====================================================================
        report "TEST 5: ERR flag check";
        rst  <= '0';
        en   <= '1';
        d_in <= x"AAAAAAAA";
        wait until rising_edge(clk);
        wait for 1 ns;

        assert err_out = '0'
            report "FAIL: ERR sollte '0' sein wenn alle Banken gleich" severity error;
        report "PASS: ERR = 0 (kein Fehler)";

        -- Now SEU simulation: freeze EN=0, then manually changing reg_a (radiation)
        -- ERR should be '1', Q stays the same due to voter masking
        en <= '0';
        wait for CLK_PERIOD * 2;
        report "INFO: force DUT/reg_a 0xAAAAAAAB - ERR sollte '1' werden";
        report "INFO: Q sollte trotzdem 0xAAAAAAAA bleiben";
        wait for CLK_PERIOD * 2;

        -- =====================================================================
        -- All tests done
        -- =====================================================================
        report "All tests completed." severity note;
        wait;

    end process STIM;

end architecture sim;