-- ================================================================================ --
-- NEORV32 Primitives - Generic Single-Port RAM (SPRAM)                             --
-- -------------------------------------------------------------------------------- --
-- Provides a single read/write port. Read-during-write behavior is irrelevant as   --
-- read and write accesses are guaranteed to be mutually exclusive.                 --
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

entity neorv32_prim_spram is
  generic (
    AWIDTH : natural; -- address width (number of bits)
    DWIDTH : natural; -- data width (number of bits)
    OUTREG : natural  -- add output register stage when 1
  );
  port (
    -- global control --
    clk_i : in std_ulogic; -- clock, rising edge
    -- read/write port --
    en_i   : in std_ulogic;                             -- access enable
    rw_i   : in std_ulogic;                             -- 0=read, 1=write
    addr_i : in std_ulogic_vector(AWIDTH - 1 downto 0); -- address
    data_i : in std_ulogic_vector(DWIDTH - 1 downto 0); -- write data
    data_o : out std_ulogic_vector(DWIDTH - 1 downto 0) -- read data
  );
end neorv32_prim_spram;

architecture neorv32_prim_spram_rtl of neorv32_prim_spram is

  type ram_t is array ((2 ** AWIDTH) - 1 downto 0) of std_ulogic_vector(DWIDTH - 1 downto 0);
  signal spram : ram_t;
  signal rdata : std_ulogic_vector(DWIDTH - 1 downto 0);

begin

  -- Memory Core ----------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  memory_large :
  if (AWIDTH > 0) generate
    memory_core : process (clk_i)
    begin
      if rising_edge(clk_i) then
        if (en_i = '1') then
          if (rw_i = '1') then
            spram(to_integer(unsigned(addr_i))) <= data_i;
          end if;
          rdata <= spram(to_integer(unsigned(addr_i)));
        end if;
      end if;
    end process memory_core;
  end generate;

  -- single entry only --
  memory_small :
  if (AWIDTH = 0) generate
    memory_core : process (clk_i)
    begin
      if rising_edge(clk_i) then
        if (en_i = '1') and (rw_i = '1') then
          rdata <= data_i;
        end if;
      end if;
    end process memory_core;
  end generate;

  -- Output Register ------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  output_register_enabled :
  if (OUTREG = 1) generate -- might improve FPGA mapping and/or timing results
    read_outreg : process (clk_i)
    begin
      if rising_edge(clk_i) then
        data_o <= rdata;
      end if;
    end process read_outreg;
  end generate;

  -- no output register --
  output_register_disabled :
  if (OUTREG = 0) generate
    data_o <= rdata;
  end generate;

end neorv32_prim_spram_rtl;

-- ================================================================================ --
-- NEORV32 Primitives - Generic True Dual-Port RAM (DPRAM)                          --
-- -------------------------------------------------------------------------------- --
-- Provides two independent read/write ports (port A and port B) accessing a        --
-- shared memory array. Intended for CPU (port A) and scrubber (port B) access.     --
-- Collision handling (simultaneous access to same address) is the responsibility   --
-- of the instantiating module, not this primitive.                                 --
-- Read-during-write behavior is irrelevant for port A as read and write accesses   --
-- are guaranteed to be mutually exclusive by the NEORV32 bus protocol.             --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_prim_dpram is
  generic (
    AWIDTH : natural; -- address width (number of bits)
    DWIDTH : natural; -- data width (number of bits)
    OUTREG : natural  -- add output register stage when 1
  );
  port (
    -- global control --
    clk_i : in std_ulogic; -- clock, rising edge
    -- port A: CPU read/write port --
    en_a_i   : in std_ulogic;                              -- access enable
    rw_a_i   : in std_ulogic;                              -- 0=read, 1=write
    addr_a_i : in std_ulogic_vector(AWIDTH - 1 downto 0);  -- address
    data_a_i : in std_ulogic_vector(DWIDTH - 1 downto 0);  -- write data
    data_a_o : out std_ulogic_vector(DWIDTH - 1 downto 0); -- read data
    -- port B: scrubber read/write port --
    en_b_i   : in std_ulogic;                             -- access enable
    rw_b_i   : in std_ulogic;                             -- 0=read, 1=write
    addr_b_i : in std_ulogic_vector(AWIDTH - 1 downto 0); -- address
    data_b_i : in std_ulogic_vector(DWIDTH - 1 downto 0); -- write data
    data_b_o : out std_ulogic_vector(DWIDTH - 1 downto 0) -- read data
  );
end neorv32_prim_dpram;

architecture neorv32_prim_dpram_rtl of neorv32_prim_dpram is

  type ram_t is array ((2 ** AWIDTH) - 1 downto 0) of std_ulogic_vector(DWIDTH - 1 downto 0);
  signal dpram   : ram_t;
  signal rdata_a : std_ulogic_vector(DWIDTH - 1 downto 0);
  signal rdata_b : std_ulogic_vector(DWIDTH - 1 downto 0);

  -- force Vivado to infer Block RAM (TDP mode) instead of distributed RAM --
  attribute ram_style          : string;
  attribute ram_style of dpram : signal is "block";

begin

  -- Memory Core Port A (CPU) -----------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  port_a_access :
  if (AWIDTH > 0) generate
    port_a_core : process (clk_i)
    begin
      if rising_edge(clk_i) then
        if (en_a_i = '1') and (rw_a_i = '1') then -- write
          dpram(to_integer(unsigned(addr_a_i))) <= data_a_i;
        end if;
        if (en_a_i = '1') and (rw_a_i = '0') then -- read
          rdata_a <= dpram(to_integer(unsigned(addr_a_i)));
        end if;
      end if;
    end process port_a_core;
  end generate;

  -- Memory Core Port B (Scrubber) ------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  port_b_access :
  if (AWIDTH > 0) generate
    port_b_core : process (clk_i)
    begin
      if rising_edge(clk_i) then
        if (en_b_i = '1') and (rw_b_i = '1') then -- write (correction)
          dpram(to_integer(unsigned(addr_b_i))) <= data_b_i;
        end if;
        if (en_b_i = '1') and (rw_b_i = '0') then -- read
          rdata_b <= dpram(to_integer(unsigned(addr_b_i)));
        end if;
      end if;
    end process port_b_core;
  end generate;

  -- Output Register Port A --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  output_register_a_enabled :
  if (OUTREG = 1) generate
    read_outreg_a : process (clk_i)
    begin
      if rising_edge(clk_i) then
        data_a_o <= rdata_a;
      end if;
    end process read_outreg_a;
  end generate;

  output_register_a_disabled :
  if (OUTREG = 0) generate
    data_a_o <= rdata_a;
  end generate;

  -- Output Register Port B --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  output_register_b_enabled :
  if (OUTREG = 1) generate
    read_outreg_b : process (clk_i)
    begin
      if rising_edge(clk_i) then
        data_b_o <= rdata_b;
      end if;
    end process read_outreg_b;
  end generate;

  output_register_b_disabled :
  if (OUTREG = 0) generate
    data_b_o <= rdata_b;
  end generate;
end neorv32_prim_dpram_rtl;