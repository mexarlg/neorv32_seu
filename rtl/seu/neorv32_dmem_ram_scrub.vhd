-- -------------------------------------------------------------------------------- --
-- NEORV32 SoC - Data Memory (DMEM) Scrubbing RAM Wrapper                           --
-- -------------------------------------------------------------------------------- --
-- Replaces neorv32_dmem with a dual port version that adds a background             --
-- scrubbing controller on Port B. Port A preserves the exact same interface         --
-- Port B is used exclusively by the internal scrubber state machine.                --
-- Collision handling (CPU write + scrubber access to same address) is managed        --
-- internally by the scrubber FSM. ECC is SECDED for 32-bit words.                   --
--                                                                                   --
-- The dual port RAM is inferred from a standard VHDL template. Vivado will          --
-- map it to BRAM36 primitives automatically. No vendor IP dependency.               --
--                                                                                   --
--      Author: Aldo Lupio - 2026                                                    --
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

entity neorv32_dmem_ram_scrub is
    generic (
        DMEM_AWIDTH : natural; -- byte address width
        DMEM_OUTREG : boolean; -- add output register stage on Port A reads
        SCRUB_START : natural; -- first word index to scrub
        SCRUB_END   : natural  -- last word index to scrub
    );
    port (
        -- Global control
        clk_i      : in std_ulogic;
        rstn_i     : in std_ulogic;
        scrub_en_i : in std_ulogic;

        -- Port A: CPU interface (same as original neorv32_dmem)
        cpu_ben_i  : in std_ulogic_vector(3 downto 0);
        cpu_rw_i   : in std_ulogic;
        cpu_addr_i : in std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
        cpu_data_i : in std_ulogic_vector(31 downto 0);
        cpu_data_o : out std_ulogic_vector(31 downto 0);

        -- Fault log (software readable)
        flog_clear_i     : in std_ulogic;
        flog_last_addr_o : out std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
        flog_count_o     : out std_ulogic_vector(7 downto 0);
        flog_overflow_o  : out std_ulogic;

        -- Scrubber status
        stat_data_valid_o : out std_ulogic;
        stat_corrected_o  : out std_ulogic;
        stat_detected_o   : out std_ulogic;
        stat_state_o      : out std_ulogic_vector(2 downto 0);
        stat_addr_o       : out std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
        stat_conflict_o   : out std_ulogic;
        stat_busy_o       : out std_ulogic;
        stat_full_pass_o  : out std_ulogic
    );
end neorv32_dmem_ram_scrub;

architecture neorv32_dmem_ram_scrub_rtl of neorv32_dmem_ram_scrub is

    -- -------------------------------------------------------------------------
    -- Component IP declarations (VIO, ILA)
    -- -------------------------------------------------------------------------
    component vio_scrub
        port (
            clk        : in std_logic;
            probe_out0 : out std_logic_vector(0 downto 0)
        );
    end component;

    component ila_scrub

        port (
            clk    : in std_logic;
            probe0 : in std_logic_vector(2 downto 0);
            probe1 : in std_logic_vector(0 downto 0);
            probe2 : in std_logic_vector(0 downto 0);
            probe3 : in std_logic_vector(0 downto 0);
            probe4 : in std_logic_vector(7 downto 0);
            probe5 : in std_logic_vector(0 downto 0)
        );
    end component;
    -- -------------------------------------------------------------------------
    -- Memory configuration
    -- -------------------------------------------------------------------------
    constant MEM_DEPTH    : natural := (2 ** DMEM_AWIDTH) / 4;
    constant WORD_ADDR_HI : natural := DMEM_AWIDTH - 1;
    constant WORD_ADDR_LO : natural := 2;

    -- -------------------------------------------------------------------------
    -- Word addresses for RAM access
    -- -------------------------------------------------------------------------
    signal addr_a : std_ulogic_vector(WORD_ADDR_HI - WORD_ADDR_LO downto 0);
    signal addr_b : std_ulogic_vector(WORD_ADDR_HI - WORD_ADDR_LO downto 0);

    -- -------------------------------------------------------------------------
    -- Scrubber FSM signals (Port B)
    -- -------------------------------------------------------------------------
    signal scrub_en    : std_ulogic;
    signal scrub_rw    : std_ulogic;
    signal scrub_addr  : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal scrub_wdata : std_ulogic_vector(31 downto 0);
    signal scrub_rdata : std_ulogic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- VIO CDC connection signals
    -- -------------------------------------------------------------------------
    signal vio_scrub_en_raw  : std_logic_vector(0 downto 0);
    signal vio_scrub_en_meta : std_ulogic;
    signal vio_scrub_en_sync : std_ulogic;

    -- -------------------------------------------------------------------------
    -- ILA CONVERSION SIGNALS
    -- -------------------------------------------------------------------------
    signal corrected_slv : std_logic_vector(0 downto 0);
    signal detected_slv  : std_logic_vector(0 downto 0);
    signal conflict_slv  : std_logic_vector(0 downto 0);
    signal full_pass_slv : std_logic_vector(0 downto 0);

begin

    -- -------------------------------------------------------------------------
    -- Word address extraction
    -- -------------------------------------------------------------------------
    addr_a <= cpu_addr_i(WORD_ADDR_HI downto WORD_ADDR_LO);
    addr_b <= scrub_addr(WORD_ADDR_HI downto WORD_ADDR_LO);

    -- -------------------------------------------------------------------------
    -- 4x byte wide true dual port RAMs
    -- Port A: CPU (byte enable controlled via generate index)
    -- Port B: Scrubber (always full word, gated by scrub_en)
    -- -------------------------------------------------------------------------
    gen_byte_ram : for i in 0 to 3 generate
        ram_inst : entity neorv32.neorv32_prim_dpram
            generic map(
                AWIDTH => DMEM_AWIDTH - 2,
                DWIDTH => 8,
                OUTREG => DMEM_OUTREG
            )
            port map(
                clk_i    => clk_i,
                en_a_i   => cpu_ben_i(i),
                rw_a_i   => cpu_rw_i,
                addr_a_i => addr_a,
                data_a_i => cpu_data_i(i * 8 + 7 downto i * 8),
                data_a_o => cpu_data_o(i * 8 + 7 downto i * 8),
                en_b_i   => scrub_en,
                rw_b_i   => scrub_rw,
                addr_b_i => addr_b,
                data_b_i => scrub_wdata(i * 8 + 7 downto i * 8),
                data_b_o => scrub_rdata(i * 8 + 7 downto i * 8)
            );
    end generate gen_byte_ram;

    -- -------------------------------------------------------------------------
    -- Scrubber FSM: drives Port B, observes Port A
    -- -------------------------------------------------------------------------
    u_scrub_fsm : entity neorv32.neorv32_scrub_fsm
        generic map(
            DMEM_AWIDTH => DMEM_AWIDTH,
            DMEM_DEPTH  => MEM_DEPTH,
            SCRUB_START => SCRUB_START,
            SCRUB_END   => SCRUB_END
        )
        port map(
            -- Global control
            clk_i      => clk_i,
            rstn_i     => rstn_i,
            scrub_en_i => vio_scrub_en_sync,
            -- CPU write monitoring
            cpu_ben_i  => cpu_ben_i,
            cpu_rw_i   => cpu_rw_i,
            cpu_addr_i => cpu_addr_i,
            cpu_data_i => cpu_data_i,
            -- Port B memory interface
            scrub_en_o   => scrub_en,
            scrub_rw_o   => scrub_rw,
            scrub_addr_o => scrub_addr,
            scrub_data_o => scrub_wdata,
            scrub_data_i => scrub_rdata,
            -- Fault log
            flog_clear_i     => flog_clear_i,
            flog_last_addr_o => flog_last_addr_o,
            flog_count_o     => flog_count_o,
            flog_overflow_o  => flog_overflow_o,
            -- Status passthrough
            stat_data_valid_o => stat_data_valid_o,
            stat_corrected_o  => stat_corrected_o,
            stat_detected_o   => stat_detected_o,
            stat_state_o      => stat_state_o,
            stat_addr_o       => stat_addr_o,
            stat_conflict_o   => stat_conflict_o,
            stat_busy_o       => stat_busy_o,
            stat_full_pass_o  => stat_full_pass_o
        );

    -- -------------------------------------------------------------------------
    -- VIO to scrub_en connection
    -- -------------------------------------------------------------------------
    vio_scrub_i : vio_scrub
    port map(
        clk        => clk_i,
        probe_out0 => vio_scrub_en_raw
    );

    -- Synchronize the VIO output (already done by vio but just in case, also change to ulogic)
    p_vio_sync : process (clk_i)
    begin
        if rising_edge(clk_i) then
            vio_scrub_en_meta <= std_ulogic(vio_scrub_en_raw(0));
            vio_scrub_en_sync <= vio_scrub_en_meta;
        end if;
    end process p_vio_sync;

    -- -------------------------------------------------------------------------
    -- ILA TO CHECK STATUS SIGNALS
    -- -------------------------------------------------------------------------
    corrected_slv(0) <= std_logic(stat_corrected_o);
    detected_slv(0)  <= std_logic(stat_detected_o);
    conflict_slv(0)  <= std_logic(stat_conflict_o);
    full_pass_slv(0) <= std_logic(stat_full_pass_o);

    ila_scrub_i : ila_scrub
    port map(
        clk    => std_logic(clk_i),
        probe0 => std_logic_vector(stat_state_o), -- state encoded on 3 bits (000Idle, 001IssRead, 010RegRead, 011Dec, 100Check, 101Enc, 110IssWrite)
        probe1 => corrected_slv,                  -- Pulse showing a correction (1bit) from scrubber
        probe2 => detected_slv,                   -- Pulse showing a detection (2bit) from scrubber
        probe3 => conflict_slv,                   -- CPU issues wr on same address as scrubber
        probe4 => std_logic_vector(flog_count_o), -- Number of detected errors (2bit, unfixable)
        probe5 => full_pass_slv                   -- Pulse of full revolution done
    );

    -- -------------------------------------------------------------------------
    -- Synthesis info
    -- -------------------------------------------------------------------------
    assert false report
    "[NEORV32] DMEM scrubbing wrapper: " &
    natural'image(MEM_DEPTH) & " words (" &
    natural'image(2 ** DMEM_AWIDTH) & " bytes), SECDED ECC"
    severity note;

end neorv32_dmem_ram_scrub_rtl;