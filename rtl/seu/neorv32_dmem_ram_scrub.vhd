-- ================================================================================ --
-- NEORV32 SoC - Data Memory (DMEM) - Scrubbing RAM Wrapper                         --
-- -------------------------------------------------------------------------------- --
-- Replaces neorv32_dmem_ram with a dual-port version that adds a background        --
-- scrubbing controller on Port B. Port A preserves the exact same interface as     --
-- the original neorv32_dmem_ram so neorv32_dmem.vhd requires no changes.           --
-- Port B is used exclusively by the internal scrubber state machine.               --
-- Collision handling (CPU write + scrubber read to same address) is managed        --
-- internally. ECC is implemented as single-bit parity per 32-bit word.             --
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

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_dmem_ram_scrub is
    generic (
        AWIDTH : natural; -- address width (byte address)
        OUTREG : natural  -- add output register stage when 1
    );
    port (
        clk_i       : in std_ulogic; -- clock, rising-edge
        rstn_i      : in std_ulogic; -- async reset, low-active
        scrubber_en : in std_ulogic; -- software-controlled scrubber enable
        -- cpu ram access
        en_i   : in std_ulogic_vector(3 downto 0);   -- byte-wise access-enable (CPU port A)
        rw_i   : in std_ulogic;                      -- 0=read, 1=write (CPU port A)
        addr_i : in std_ulogic_vector(31 downto 0);  -- full byte address (CPU port A)
        data_i : in std_ulogic_vector(31 downto 0);  -- write data (CPU port A)
        data_o : out std_ulogic_vector(31 downto 0); -- read data, sync (CPU port A)
        -- status/debug --
        stat_error_det_o : out std_ulogic;
        stat_error_fix_o : out std_ulogic;
        stat_state_o     : out std_ulogic_vector(2 downto 0);
        stat_ptr_o       : out std_ulogic_vector(AWIDTH - 3 downto 0);
        stat_conflict_o  : out std_ulogic;
        stat_busy_o      : out std_ulogic;
        stat_full_pass_o : out std_ulogic
    );
end neorv32_dmem_ram_scrub;

architecture neorv32_dmem_ram_scrub_rtl of neorv32_dmem_ram_scrub is

    -- memory depth in 32-bit words
    constant MEM_DEPTH : natural := (2 ** AWIDTH) / 4;

    -- Port B internal signals (FSM ? DPRAM)
    signal scrub_en_b   : std_ulogic;                             -- FSM single-bit enable
    signal scrub_rw_b   : std_ulogic;                             -- FSM read/write
    signal scrub_addr_b : std_ulogic_vector(AWIDTH - 3 downto 0); -- FSM word address
    signal scrub_din_b  : std_ulogic_vector(31 downto 0);         -- FSM write data
    signal scrub_dout_b : std_ulogic_vector(31 downto 0);         -- DPRAM read data to FSM

    -- Port B byte-lane enable (scrubber always accesses full words)
    signal scrub_ben_b : std_ulogic_vector(3 downto 0);

begin

    -- =========================================================================
    -- Port B byte enables ? scrubber accesses full 32-bit words only
    -- =========================================================================
    scrub_ben_b <= (others => scrub_en_b);
    -- =========================================================================
    -- 4x byte-wide dual-port RAMs
    -- Port A = CPU (directly wired from entity ports)
    -- Port B = scrubber (driven by FSM instance below)
    -- =========================================================================
    ram_gen :
    for i in 0 to 3 generate
        ram_inst : entity neorv32.neorv32_prim_dpram
            generic map(
                AWIDTH => AWIDTH - 2,
                DWIDTH => 8,
                OUTREG => OUTREG
            )
            port map(
                clk_i => clk_i,
                -- Port A ? CPU
                en_a_i   => en_i(i),
                rw_a_i   => rw_i,
                addr_a_i => addr_i(AWIDTH - 1 downto 2),
                data_a_i => data_i(i * 8 + 7 downto i * 8),
                data_a_o => data_o(i * 8 + 7 downto i * 8),
                -- Port B ? scrubber
                en_b_i   => scrub_ben_b(i),
                rw_b_i   => scrub_rw_b,
                addr_b_i => scrub_addr_b,
                data_b_i => scrub_din_b(i * 8 + 7 downto i * 8),
                data_b_o => scrub_dout_b(i * 8 + 7 downto i * 8)
            );
    end generate;

    -- =========================================================================
    -- Scrubber FSM ? drives Port B, observes Port A for collisions
    -- =========================================================================
    scrub_fsm_inst : entity neorv32.neorv32_scrub_fsm
        generic map(
            AWIDTH    => AWIDTH,
            MEM_DEPTH => MEM_DEPTH
        )
        port map(
            clk_i       => clk_i,
            rstn_i      => rstn_i,
            scrubber_en => scrubber_en,
            -- CPU observation (directly wired from entity ports)
            cpu_en_i   => en_i,
            cpu_rw_i   => rw_i,
            cpu_addr_i => addr_i,
            cpu_data_i => data_i,
            -- Port B memory interface
            mem_en_b_o   => scrub_en_b,
            mem_rw_b_o   => scrub_rw_b,
            mem_addr_b_o => scrub_addr_b,
            mem_data_b_o => scrub_din_b,
            mem_data_b_i => scrub_dout_b,
            -- status/debug passthrough
            stat_error_det_o => stat_error_det_o,
            stat_error_fix_o => stat_error_fix_o,
            stat_state_o     => stat_state_o,
            stat_ptr_o       => stat_ptr_o,
            stat_conflict_o  => stat_conflict_o,
            stat_busy_o      => stat_busy_o,
            stat_full_pass_o => stat_full_pass_o
        );

    -- notifier
    assert false report
    "[NEORV32] Using scrubbing DMEM RAM component (" &
    natural'image(2 ** AWIDTH) & " bytes, parity ECC on Port B)."
    severity note;

end neorv32_dmem_ram_scrub_rtl;