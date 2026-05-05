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