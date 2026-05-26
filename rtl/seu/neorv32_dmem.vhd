-- -------------------------------------------------------------------------------- --
-- NEORV32 SoC - Processor-Internal Data Memory (DMEM)                               --
-- -------------------------------------------------------------------------------- --
-- Replaces the default neorv32_dmem with a scrubbing capable version.               --
-- Translates the internal NEORV32 bus interface (bus_req_t / bus_rsp_t)              --
-- into the signals expected by neorv32_dmem_ram_scrub.                               --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32               --
-- Copyright (c) NEORV32 contributors.                                               --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                   --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                 --
-- SPDX-License-Identifier: BSD-3-Clause                                             --
-- -------------------------------------------------------------------------------- --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_dmem is
    generic (
        DMEM_SIZE : natural; -- memory size in bytes, has to be a power of 2, min 4
        OUTREG_EN : boolean  -- implement output register stage
    );
    port (
        clk_i     : in std_ulogic;
        rstn_i    : in std_ulogic;
        bus_req_i : in bus_req_t;
        bus_rsp_o : out bus_rsp_t
    );
end neorv32_dmem;

architecture neorv32_dmem_rtl of neorv32_dmem is

    -- -------------------------------------------------------------------------
    -- Auto-configuration
    -- -------------------------------------------------------------------------
    constant awidth_c : natural := index_size_f(DMEM_SIZE);
    constant outreg_c : natural := cond_sel_natural_f(OUTREG_EN, 1, 0);

    -- -------------------------------------------------------------------------
    -- Local signals
    -- -------------------------------------------------------------------------
    signal rdata : std_ulogic_vector(31 downto 0);
    signal wren  : std_ulogic;
    signal rden  : std_ulogic_vector(1 downto 0);
    signal ben   : std_ulogic_vector(3 downto 0);

    -- -------------------------------------------------------------------------
    -- Scrubber start / end memory word addresses (519 for sw test with 512 test words filled on dmem)
    -- -------------------------------------------------------------------------
    constant C_SCRUB_START : natural := 0;
    constant C_SCRUB_END   : natural := 511;

begin

    -- -------------------------------------------------------------------------
    -- Byte enables: active only when bus strobe is asserted
    -- -------------------------------------------------------------------------
    ben <= bus_req_i.ben when (bus_req_i.stb = '1') else
        (others => '0');

    -- -------------------------------------------------------------------------
    -- DMEM RAM with scrubber instantiation
    -- -------------------------------------------------------------------------
    dmem_ram_inst : entity neorv32.neorv32_dmem_ram_scrub
        generic map(
            DMEM_AWIDTH => awidth_c,
            DMEM_OUTREG => OUTREG_EN,
            SCRUB_START => C_SCRUB_START,
            SCRUB_END   => C_SCRUB_END
        )
        port map(
            -- Global control
            clk_i      => clk_i,
            rstn_i     => rstn_i,
            scrub_en_i => '0',
            -- CPU interface
            cpu_ben_i  => ben,
            cpu_rw_i   => bus_req_i.rw,
            cpu_addr_i => bus_req_i.addr(awidth_c - 1 downto 0),
            cpu_data_i => bus_req_i.data,
            cpu_data_o => rdata,
            -- Fault log (directly active clear for later sw access)
            flog_clear_i     => '0',
            flog_last_addr_o => open,
            flog_count_o     => open,
            flog_overflow_o  => open,
            -- Scrubber status (directly active for later sw access)
            stat_data_valid_o => open,
            stat_corrected_o  => open,
            stat_detected_o   => open,
            stat_state_o      => open,
            stat_addr_o       => open,
            stat_conflict_o   => open,
            stat_busy_o       => open,
            stat_full_pass_o  => open
        );

    -- -------------------------------------------------------------------------
    -- Bus handshake
    -- -------------------------------------------------------------------------
    p_bus_handshake : process (rstn_i, clk_i)
    begin
        if (rstn_i = '0') then
            wren <= '0';
            rden <= (others => '0');
        elsif rising_edge(clk_i) then
            wren <= bus_req_i.stb and bus_req_i.rw;
            rden <= rden(0) & (bus_req_i.stb and (not bus_req_i.rw));
        end if;
    end process p_bus_handshake;

    -- -------------------------------------------------------------------------
    -- Bus response
    -- -------------------------------------------------------------------------
    bus_rsp_o.data <= rdata when (rden(outreg_c) = '1') else
    (others => '0');
    bus_rsp_o.err <= '0';
    bus_rsp_o.ack <= rden(outreg_c) or wren;

end neorv32_dmem_rtl;