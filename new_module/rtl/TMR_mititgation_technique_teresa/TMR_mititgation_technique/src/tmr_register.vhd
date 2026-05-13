-- =============================================================================
-- File        : tmr_register.vhd
-- Project     : NOERV32 - Space Radiation Mitigation
-- Description : Triple Modular Redundancy (TMR) 32-bit register with
--               bitwise 2-of-3 majority voter.
--
-- Architecture:
--   ┌──────────┐
--   │  D input │
--   └────┬─────┘
--        │ (replicated x3)
--   ┌────▼─────┐  ┌──────────┐   ┌──────────┐
--   │  REG_A   │  │  REG_B   │   │  REG_C   │
--   └────┬─────┘  └────┬─────┘   └─── ┬─────┘
--        └─────────────┴──────────────┘
--                      │
--              ┌───────▼────────┐
--              │ MAJORITY VOTER │  (bitwise, 2-of-3)
--              └───────┬────────┘
--                      │
--                 ┌────▼────┐
--                 │  Q out  │
--                 └─────────┘
--
-- Majority logic (per bit):
--   Q(i) = (A(i) AND B(i)) OR (A(i) AND C(i)) OR (B(i) AND C(i))
--
-- Typical SEU behaviour:
--   - 0 upsets  → correct output
--   - 1 upset   → masked by voter
--   - 2+ upsets → undetected error (acceptable for single-event mitigation)
-- =============================================================================


library ieee;
use ieee.std_logic_1164.all;
-- =============================================================================
-- Entity : majority_voter
-- Purpose: Pure combinational bitwise 2-of-3 majority voter (32-bit).
--          Instantiated inside tmr_register but can also be reused standalone.
-- =============================================================================
entity majority_voter is
    port (
        A : in  std_logic_vector(31 downto 0);  -- Output of register bank A
        B : in  std_logic_vector(31 downto 0);  -- Output of register bank B
        C : in  std_logic_vector(31 downto 0);  -- Output of register bank C
        Y : out std_logic_vector(31 downto 0)   -- Majority-voted output
    );
end entity majority_voter;

architecture rtl of majority_voter is
begin

    -- -------------------------------------------------------------------------
    -- BITWISE majority: Y(i) = 1 if at least 2 of {A(i), B(i), C(i)} are 1
    -- No sequential logic here — purely combinational.
    -- -------------------------------------------------------------------------
    Y <= (A and B) or (A and C) or (B and C);

end architecture rtl;


library ieee;
use ieee.std_logic_1164.all;
-- =============================================================================
-- Entity : tmr_register
-- Purpose: 32-bit TMR-protected register.
--          Three identical register banks are driven by the same D input and
--          clock. Their outputs are fed into the majority voter to produce a
--          single fault-tolerant output Q.
--
-- Ports:
--   CLK  - System clock (rising-edge triggered)
--   RST  - Synchronous active-high reset
--   EN   - Clock enable (register only updates when EN = '1')
--   D    - 32-bit data input (written to all three banks simultaneously)
--   Q    - 32-bit majority-voted data output
-- =============================================================================
entity tmr_register is
    port (
        CLK : in  std_logic;
        RST : in  std_logic;                     -- Synchronous, active-high
        EN  : in  std_logic;                     -- Clock enable, to hold Q value when '0', might get important for Scrubbing
        D   : in  std_logic_vector(31 downto 0);
        Q   : out std_logic_vector(31 downto 0);
        ERR : out std_logic                      -- Error flag indicating a detected mismatch among the three banks (optional, for monitoring purposes)
    );
end entity tmr_register;

architecture rtl of tmr_register is

    -- -------------------------------------------------------------------------
    -- Internal signals: three redundant register banks
    -- -------------------------------------------------------------------------
    signal reg_a : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_b : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_c : std_logic_vector(31 downto 0) := (others => '0');

    -- Voter output
    signal voted_q : std_logic_vector(31 downto 0);

    -- -- Component declaration for the majority voter
    -- component majority_voter is
    --     port (
    --         A : in  std_logic_vector(31 downto 0);
    --         B : in  std_logic_vector(31 downto 0);
    --         C : in  std_logic_vector(31 downto 0);
    --         Y : out std_logic_vector(31 downto 0)
    --     );
    -- end component majority_voter;

begin

    -- -------------------------------------------------------------------------
    -- Register bank A
    -- Each bank is an independent process so that synthesis can place them in
    -- physically separate locations on the die / FPGA fabric, increasing the
    -- probability that a single particle strike only upsets one bank.
    -- -------------------------------------------------------------------------
    BANK_A : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                reg_a <= (others => '0');
            elsif EN = '1' then
                reg_a <= D;
            end if;
        end if;
    end process BANK_A;

    -- -------------------------------------------------------------------------
    -- Register bank B
    -- -------------------------------------------------------------------------
    BANK_B : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                reg_b <= (others => '0');
            elsif EN = '1' then
                reg_b <= D;
            end if;
        end if;
    end process BANK_B;

    -- -------------------------------------------------------------------------
    -- Register bank C
    -- -------------------------------------------------------------------------
    BANK_C : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                reg_c <= (others => '0');
            elsif EN = '1' then
                reg_c <= D;
            end if;
        end if;
    end process BANK_C;

    -- -------------------------------------------------------------------------
    -- Majority voter instantiation
    -- -------------------------------------------------------------------------
    VOTER : entity work.majority_voter
        port map (
            A => reg_a,
            B => reg_b,
            C => reg_c,
            Y => voted_q
        );

    -- Drive the output
    Q <= voted_q;

    -- Error flag: '1' wenn mindestens eine Bank vom Voter abweicht
    ERR <= '1' when (reg_a /= reg_b) or
                      (reg_a /= reg_c) or
                      (reg_b /= reg_c)
            else '0';

    --     -- geht nicht direkt:
    -- ERROR <= (reg_a /= reg_b) or (reg_a /= reg_c) or (reg_b /= reg_c);
    -- --        boolean              boolean              boolean
    -- --        aber ERROR ist std_logic!

end architecture rtl;
