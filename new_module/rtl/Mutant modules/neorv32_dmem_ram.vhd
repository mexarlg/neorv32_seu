-- ================================================================================ --
-- NEORV32 SoC - Data Memory (DMEM) - RAM Primitive Wrapper                         --
-- -------------------------------------------------------------------------------- --
-- Replace this file by a more efficient technology-specific IP wrapper. The read-  --
-- during-write behavior is irrelevant as read/write accesses are mutual exclusive. --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.seu_pkg.all;

entity neorv32_dmem_ram is
  generic (
    AWIDTH : natural; -- address width (byte address)
    OUTREG : natural  -- add output register stage when 1
  );
  port (
    clk_i  : in  std_ulogic;                       -- clock, rising-edge
    en_i   : in  std_ulogic_vector(3 downto 0);   -- byte-wise access-enable
    rw_i   : in  std_ulogic;                       -- 0=read, 1=write
    addr_i : in  std_ulogic_vector(31 downto 0);  -- full byte address
    data_i : in  std_ulogic_vector(31 downto 0);  -- write data
    data_o : out std_ulogic_vector(31 downto 0);  -- read data, sync

    -- SEU injection fault setting ----------------------------------
    rst_n           : in std_ulogic;
    fault_enable    : in  std_ulogic;
    fault_trigger   : in  std_ulogic;
    at_bit          : out std_ulogic_vector(4 downto 0);
    faulted_address : out std_ulogic_vector(31 downto 0);
    clean_data      : out std_ulogic_vector(31 downto 0);
    faulted_data    : out std_ulogic_vector(31 downto 0);

    -- MBU injection fault setting ---------------------------------
    fault_MBU       : in  std_ulogic;
    mask            : in  std_ulogic_vector(31 downto 0)
    
  );
end neorv32_dmem_ram;

architecture neorv32_dmem_ram_rtl of neorv32_dmem_ram is
-----------------------------------------------------------------------------
-- Fault Injection Control
-- --------------------------------------------------------------------------
-- The DMEM wrapper centrally generates:
--   - a pseudo-random target word address,
--   - a fault mask describing which bits will be corrupted.
--
-- Two fault modes are supported:
--
--   * SBU (Single-Bit Upset):
--       exactly one randomly selected bit is flipped.
--
--   * MBU (Multi-Bit Upset):
--       the user-provided mask directly defines corrupted bits.
--
-- The generated 32-bit fault mask is then distributed across the four
-- byte-wide SPRAM instances.
-----------------------------------------------------------------------------

  -- Signals
  signal fault_word_addr : std_ulogic_vector(AWIDTH-3 downto 0);
  signal randvect        : std_ulogic_vector(31 downto 0) := x"A5C3F19B";
  signal next_rand       : std_ulogic_vector(31 downto 0);  -- combinatorial next LFSR state
  signal atbit_comb      : std_ulogic_vector(4 downto 0);   -- combinatorial target bit index
  signal faulted_bit     : std_ulogic_vector(31 downto 0);  -- combinatorial fault mask

begin

  -- Notifier --
  assert false report
    "[NEORV32] Using default DMEM RAM component (" &
    natural'image(2**AWIDTH) & " bytes)." severity note;

  ---------------------------------------------------------------------------
  -- Combinatorial LFSR Advancement
  ---------------------------------------------------------------------------
  next_rand  <= fibo_lfsr(randvect);

  -- Target bit index for SBU (derived combinatorially from next_rand)
  atbit_comb <= next_rand(4 downto 0);

  -- Word-aligned target address (derived combinatorially from next_rand)
  fault_word_addr <= next_rand(AWIDTH-3 downto 0);

  -- Full byte address reconstruction (2 LSBs forced to 00 for word alignment)
  faulted_address <= (31 downto AWIDTH => '0') & fault_word_addr & "00";

  ---------------------------------------------------------------------------
  -- Combinatorial Fault Mask Generation (SBU one-hot or MBU external mask)
  -- ---------------------------------------------------------------------------
  fault_mask_comb : process(atbit_comb, fault_MBU, mask)

    variable fault_mask : std_ulogic_vector(31 downto 0);

  begin

    -- Build one-hot mask from the target bit index (used for SBU)
    fault_mask := (others => '0');
    fault_mask(to_integer(unsigned(atbit_comb))) := '1';

    if fault_MBU = '1' then

      -- Multi-Bit Upset: use the externally provided bit mask
      faulted_bit <= mask;

    else

      -- Single-Bit Upset: inject exactly one random bit flip
      faulted_bit <= fault_mask;

    end if;

  end process fault_mask_comb;

  ---------------------------------------------------------------------------
  -- Sequential Process: LFSR Advancement and at_bit Debug Output
  -- ---------------------------------------------------------------------------
  -- On each active trigger, register the current next_rand as the new LFSR
  -- state and capture the injected bit index for debug readback.
  ---------------------------------------------------------------------------
  seq_proc : process(clk_i)
  begin

    if rising_edge(clk_i) then

      if (rst_n = '0') then                        -- sync reset, active low

        randvect <= x"A5C3F19B";
        at_bit   <= (others => '0');

      elsif (fault_enable = '1') and (fault_trigger = '1') then
        
        -- Advance the LFSR for the next injection cycle
        randvect <= next_rand;

        if fault_MBU = '1' then

          -- No meaningful single bit index for MBU mode
          at_bit <= (others => '0');
          
        else

          -- Record which bit was flipped this cycle
          at_bit <= atbit_comb;

        end if;
      end if;
    end if;
  end process seq_proc;
  

  ---------------------------------------------------------------------------
  -- Physical DMEM Organization
  -- ---------------------------------------------------------------------------
  -- DMEM is implemented as four independent byte-wide SPRAM instances.
  ---------------------------------------------------------------------------
  ram_gen :
  for i in 0 to 3 generate
  begin
    ram_inst : entity work.neorv32_prim_spram
      generic map (
        AWIDTH => AWIDTH-2,
        DWIDTH => 8,
        OUTREG => OUTREG
      )
      port map (
        clk_i           => clk_i,
        en_i            => en_i(i),
        rw_i            => rw_i,
        addr_i          => addr_i(AWIDTH-1 downto 2),
        data_i          => data_i(i*8+7 downto i*8),
        data_o          => data_o(i*8+7 downto i*8),
        fault_enable    => fault_enable,
        fault_trigger   => fault_trigger,
        faulted_address => fault_word_addr,
        faulted_bit     => faulted_bit(i*8+7 downto i*8),
        clean_data      => clean_data(i*8+7 downto i*8),
        faulted_data    => faulted_data(i*8+7 downto i*8)
      );
  end generate;

end neorv32_dmem_ram_rtl;