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

entity neorv32_dmem_scrub is
    generic (
        DMEM_AWIDTH : natural; -- byte address width
        DMEM_OUTREG : boolean  -- add output register stage on Port A reads
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
        flog_count_o     : out std_ulogic_vector(2 downto 0);
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
end neorv32_dmem_scrub;

architecture neorv32_dmem_scrub_rtl of neorv32_dmem_scrub is

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
    -- Port A read data (before optional output register)
    -- -------------------------------------------------------------------------
    signal mem_a_rdata  : std_ulogic_vector(31 downto 0);
    signal cpu_data_reg : std_ulogic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- Scrubber FSM signals (Port B)
    -- -------------------------------------------------------------------------
    signal scrub_en    : std_ulogic;
    signal scrub_rw    : std_ulogic;
    signal scrub_addr  : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal scrub_wdata : std_ulogic_vector(31 downto 0);
    signal scrub_rdata : std_ulogic_vector(31 downto 0);

begin

    -- -------------------------------------------------------------------------
    -- Word address extraction
    -- -------------------------------------------------------------------------
    addr_a <= cpu_addr_i(WORD_ADDR_HI downto WORD_ADDR_LO);
    addr_b <= scrub_addr(WORD_ADDR_HI downto WORD_ADDR_LO);

    -- -------------------------------------------------------------------------
    -- 4x byte-wide true dual-port RAMs
    --
    -- Each instance is 8 bits wide and MEM_DEPTH deep. This follows the
    -- standard Vivado true dual-port BRAM inference template: one process
    -- per port, synchronous read and write, no async reset on storage.
    --
    -- Port A: CPU (byte enable controlled via generate index)
    -- Port B: Scrubber (always full word, gated by scrub_en)
    -- -------------------------------------------------------------------------
    gen_byte_ram : for i in 0 to 3 generate

        signal ram : std_ulogic_vector(7 downto 0);

        -- Per-byte-lane RAM array
        type ram_t is array (0 to MEM_DEPTH - 1) of std_ulogic_vector(7 downto 0);
        signal mem : ram_t := (others => (others => '0'));

    begin

        -- Port A: CPU access
        p_port_a : process (clk_i)
        begin
            if rising_edge(clk_i) then
                if (cpu_ben_i(i) = '1') and (cpu_rw_i = '1') then
                    mem(to_integer(unsigned(addr_a))) <= cpu_data_i(i * 8 + 7 downto i * 8);
                end if;
                mem_a_rdata(i * 8 + 7 downto i * 8) <= mem(to_integer(unsigned(addr_a)));
            end if;
        end process p_port_a;

        -- Port B: Scrubber access
        p_port_b : process (clk_i)
        begin
            if rising_edge(clk_i) then
                if (scrub_en = '1') then
                    if (scrub_rw = '1') then
                        mem(to_integer(unsigned(addr_b))) <= scrub_wdata(i * 8 + 7 downto i * 8);
                    end if;
                    scrub_rdata(i * 8 + 7 downto i * 8) <= mem(to_integer(unsigned(addr_b)));
                end if;
            end if;
        end process p_port_b;

    end generate gen_byte_ram;

    -- -------------------------------------------------------------------------
    -- Port A output register (optional)
    -- -------------------------------------------------------------------------
    gen_outreg : if DMEM_OUTREG generate
        p_outreg : process (clk_i)
        begin
            if rising_edge(clk_i) then
                cpu_data_reg <= mem_a_rdata;
            end if;
        end process p_outreg;
        cpu_data_o <= cpu_data_reg;
    end generate gen_outreg;

    gen_no_outreg : if not DMEM_OUTREG generate
        cpu_data_o <= mem_a_rdata;
    end generate gen_no_outreg;

    -- -------------------------------------------------------------------------
    -- Scrubber FSM: drives Port B, observes Port A
    -- -------------------------------------------------------------------------
    u_scrub_fsm : entity work.neorv32_scrub_fsm
        generic map(
            DMEM_AWIDTH => DMEM_AWIDTH,
            DMEM_DEPTH  => MEM_DEPTH
        )
        port map(
            -- Global control
            clk_i      => clk_i,
            rstn_i     => rstn_i,
            scrub_en_i => scrub_en_i,
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
            stat_corrected_o => stat_corrected_o,
            stat_detected_o  => stat_detected_o,
            stat_state_o     => stat_state_o,
            stat_addr_o      => stat_addr_o,
            stat_conflict_o  => stat_conflict_o,
            stat_busy_o      => stat_busy_o,
            stat_full_pass_o => stat_full_pass_o
        );

    -- -------------------------------------------------------------------------
    -- Synthesis info
    -- -------------------------------------------------------------------------
    assert false report
    "[NEORV32] DMEM scrubbing wrapper: " &
    natural'image(MEM_DEPTH) & " words (" &
    natural'image(2 ** DMEM_AWIDTH) & " bytes), SECDED ECC"
    severity note;

end neorv32_dmem_scrub_rtl;