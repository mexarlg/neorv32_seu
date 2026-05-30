-- -------------------------------------------------------------------------------- --
-- NEORV32 SoC - Data Memory (DMEM) Scrubbing RAM Wrapper                           --
-- -------------------------------------------------------------------------------- --
-- Replaces neorv32_dmem with a dual port version that adds a background             --
-- scrubbing controller on Port B. Port A preserves the exact same interface         --
-- Port B is used exclusively by the internal scrubber state machine.                --
-- Collision handling (CPU write + scrubber access to same address) is managed        --
-- internally by the scrubber FSM. ECC is SECDED for 32-bit words.                   --
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
            probe_out0 : out std_logic_vector(0 downto 0);
            probe_out1 : out std_logic_vector(0 downto 0);
            probe_out2 : out std_logic_vector(DMEM_AWIDTH - 3 downto 0);
            probe_out3 : out std_logic_vector(31 downto 0)
        );
    end component;

    component ila_scrub
        port (
            clk     : in std_logic;
            probe0  : in std_logic_vector(0 downto 0);
            probe1  : in std_logic_vector(3 downto 0);
            probe2  : in std_logic_vector(14 downto 0);
            probe3  : in std_logic_vector(31 downto 0);
            probe4  : in std_logic_vector(0 downto 0);
            probe5  : in std_logic_vector(0 downto 0);
            probe6  : in std_logic_vector(31 downto 0);
            probe7  : in std_logic_vector(31 downto 0);
            probe8  : in std_logic_vector(2 downto 0);
            probe9  : in std_logic_vector(14 downto 0);
            probe10 : in std_logic_vector(0 downto 0);
            probe11 : in std_logic_vector(0 downto 0);
            probe12 : in std_logic_vector(0 downto 0);
            probe13 : in std_logic_vector(0 downto 0);
            probe14 : in std_logic_vector(0 downto 0);
            probe15 : in std_logic_vector(7 downto 0);
            probe16 : in std_logic_vector(0 downto 0)
        );
    end component;

    -- -------------------------------------------------------------------------
    -- Memory configuration
    -- -------------------------------------------------------------------------
    constant MEM_DEPTH    : natural := (2 ** DMEM_AWIDTH) / 4;
    constant WORD_ADDR_HI : natural := DMEM_AWIDTH - 1;
    constant WORD_ADDR_LO : natural := 2;
    constant WORD_IDX_W   : natural := DMEM_AWIDTH - 2; -- word index width

    -- -------------------------------------------------------------------------
    -- Word addresses for RAM access
    -- -------------------------------------------------------------------------
    signal addr_a : std_ulogic_vector(WORD_ADDR_HI - WORD_ADDR_LO downto 0);
    signal addr_b : std_ulogic_vector(WORD_ADDR_HI - WORD_ADDR_LO downto 0);

    -- -------------------------------------------------------------------------
    -- Scrubber FSM signals (Port B)
    -- -------------------------------------------------------------------------
    signal scrub_portb_en : std_ulogic;
    signal scrub_rw       : std_ulogic;
    signal scrub_addr     : std_ulogic_vector(DMEM_AWIDTH - 1 downto 0);
    signal scrub_wdata    : std_ulogic_vector(31 downto 0);
    signal scrub_rdata    : std_ulogic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- Port B inputs after the injection mux
    -- -------------------------------------------------------------------------
    signal portb_en   : std_ulogic;
    signal portb_rw   : std_ulogic;
    signal portb_addr : std_ulogic_vector(WORD_ADDR_HI - WORD_ADDR_LO downto 0);
    signal portb_data : std_ulogic_vector(31 downto 0);

    -- -------------------------------------------------------------------------
    -- VIO CDC connection signals
    -- -------------------------------------------------------------------------
    signal vio_scrub_en_raw    : std_logic_vector(0 downto 0);
    signal vio_scrub_en_meta   : std_ulogic;
    signal vio_scrub_en_sync   : std_ulogic;
    signal scrubber_is_enabled : std_ulogic;

    -- -------------------------------------------------------------------------
    -- SEU injection signals from vio
    -- -------------------------------------------------------------------------
    signal vio_inj_arm_raw   : std_logic_vector(0 downto 0); -- seu injection enable from vio
    signal vio_inj_arm_meta  : std_ulogic;                   -- seu injection enable from vio in ulogic
    signal vio_inj_arm_sync  : std_ulogic;                   -- seu injection enable from vio in ulogic sync
    signal vio_inj_arm_sync2 : std_ulogic;                   -- seu injection enable from vio in ulogic sync2

    signal vio_inj_addr : std_logic_vector(WORD_IDX_W - 1 downto 0); -- address of seu injection in bram (word index)
    signal vio_inj_data : std_logic_vector(31 downto 0);             -- data to be written into memory (data pre-known)
    signal inj_addr     : std_ulogic_vector(WORD_IDX_W - 1 downto 0);-- address of seu injection in bram (word index) converted to ulogic
    signal inj_data     : std_ulogic_vector(31 downto 0); -- data to be written into memory (data pre-known) converted to ulogic

    signal inj_pending : std_ulogic; -- request of injection asserted, waiting for a free port B
    signal inj_fire    : std_ulogic; -- drives the injection write in 1 cycle 
    signal portb_idle  : std_ulogic; -- scrubber not using port B

    -- -------------------------------------------------------------------------
    -- ILA CONVERSION SIGNALS
    -- -------------------------------------------------------------------------
    signal cpu_rw_slv          : std_logic_vector(0 downto 0);
    signal scrub_en_slv        : std_logic_vector(0 downto 0);
    signal scrub_rw_slv        : std_logic_vector(0 downto 0);
    signal stat_busy_slv       : std_logic_vector(0 downto 0);
    signal stat_full_pass_slv  : std_logic_vector(0 downto 0);
    signal stat_corrected_slv  : std_logic_vector(0 downto 0);
    signal stat_detected_slv   : std_logic_vector(0 downto 0);
    signal stat_data_valid_slv : std_logic_vector(0 downto 0);
    signal stat_conflict_slv   : std_logic_vector(0 downto 0);

begin

    -- -------------------------------------------------------------------------
    -- Word address extraction
    -- -------------------------------------------------------------------------
    addr_a <= cpu_addr_i(WORD_ADDR_HI downto WORD_ADDR_LO);
    addr_b <= scrub_addr(WORD_ADDR_HI downto WORD_ADDR_LO);

    -- -------------------------------------------------------------------------
    -- PORT B BRAM MUX: inj_fire asserted when Port B idle and a request is latched
    -- -------------------------------------------------------------------------
    portb_en <= '1' when (inj_fire = '1') else
        scrub_portb_en;
    portb_rw <= '1' when (inj_fire = '1') else
        scrub_rw;
    portb_addr <= inj_addr when (inj_fire = '1') else
        addr_b;
    portb_data <= inj_data when (inj_fire = '1') else
        scrub_wdata;

    -- -------------------------------------------------------------------------
    -- 4x byte wide true dual port RAMs
    -- Port A: CPU (byte enable controlled via generate index)
    -- Port B: Scrubber / Seu injection (scrubber priority)
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
                en_b_i   => portb_en,
                rw_b_i   => portb_rw,
                addr_b_i => portb_addr,
                data_b_i => portb_data(i * 8 + 7 downto i * 8),
                data_b_o => scrub_rdata(i * 8 + 7 downto i * 8)
            );
    end generate gen_byte_ram;

    -- -------------------------------------------------------------------------
    -- Scrubber FSM: drives Port B (via the mux), observes Port A
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
            scrub_en_i => scrubber_is_enabled,
            -- CPU write monitoring
            cpu_ben_i  => cpu_ben_i,
            cpu_rw_i   => cpu_rw_i,
            cpu_addr_i => cpu_addr_i,
            cpu_data_i => cpu_data_i,
            -- Port B memory interface
            scrub_en_o   => scrub_portb_en,
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
    -- VIO: INPUTS REGISTRATION (SEU INJECTION + SCRUBBER ENABLE)
    -- -------------------------------------------------------------------------
    vio_scrub_i : vio_scrub
    port map(
        clk        => clk_i,
        probe_out0 => vio_scrub_en_raw, --   probe_out0 (1)  : enables scrubbber
        probe_out1 => vio_inj_arm_raw,  --   probe_out1 (1)  : enables request to issue seu
        probe_out2 => vio_inj_addr,     --   probe_out2 (13) : word address of seu injection
        probe_out3 => vio_inj_data      --   probe_out3 (32) : corrupted data to be inserted (seu)
    );

    p_vio_sync : process (clk_i)
    begin
        if rising_edge(clk_i) then
            -- scrub enable
            vio_scrub_en_meta <= std_ulogic(vio_scrub_en_raw(0));
            vio_scrub_en_sync <= vio_scrub_en_meta;
            -- inject arm (extra stage used for rising edge detect)
            vio_inj_arm_meta  <= std_ulogic(vio_inj_arm_raw(0));
            vio_inj_arm_sync  <= vio_inj_arm_meta;
            vio_inj_arm_sync2 <= vio_inj_arm_sync;
        end if;
    end process p_vio_sync;

    -- -------------------------------------------------------------------------
    -- SEU INJECTION MODULE
    -- -------------------------------------------------------------------------
    scrubber_is_enabled <= scrub_en_i or vio_scrub_en_sync;
    portb_idle          <= '1' when (scrub_portb_en = '0' or scrubber_is_enabled = '0') else
        '0';

    inj_addr <= std_ulogic_vector(vio_inj_addr);
    inj_data <= std_ulogic_vector(vio_inj_data);

    p_inject : process (rstn_i, clk_i)
        variable arm_edge   : std_ulogic;
        variable scrub_word : std_ulogic_vector(WORD_IDX_W - 1 downto 0);
    begin
        if (rstn_i = '0') then
            inj_pending <= '0';
            inj_fire    <= '0';

        elsif rising_edge(clk_i) then
            inj_fire <= '0';

            -- rising edge of the synchronized arm bit
            arm_edge := vio_inj_arm_sync and (not vio_inj_arm_sync2);

            -- seu enable detected, request injection
            if (arm_edge = '1') then
                inj_pending <= '1';
            end if;

            -- update address of seu injection
            scrub_word := scrub_addr(WORD_ADDR_HI downto WORD_ADDR_LO);

            -- issue injection when port B is idle
            if (inj_pending = '1') and (portb_idle = '1') and
                ((scrubber_is_enabled = '0') or (scrub_word /= inj_addr)) then
                inj_fire    <= '1';
                inj_pending <= '0';
            end if;
        end if;
    end process p_inject;

    -- -------------------------------------------------------------------------
    -- ILA TO CHECK STATUS SIGNALS
    -- -------------------------------------------------------------------------
    cpu_rw_slv(0)          <= std_logic(cpu_rw_i);
    scrub_en_slv(0)        <= std_logic(scrub_portb_en);
    scrub_rw_slv(0)        <= std_logic(scrub_rw);
    stat_busy_slv(0)       <= std_logic(stat_busy_o);
    stat_full_pass_slv(0)  <= std_logic(stat_full_pass_o);
    stat_corrected_slv(0)  <= std_logic(stat_corrected_o);
    stat_detected_slv(0)   <= std_logic(stat_detected_o);
    stat_data_valid_slv(0) <= std_logic(stat_data_valid_o);
    stat_conflict_slv(0)   <= std_logic(stat_conflict_o);

    -- ILA instance
    u_ila_scrub : ila_scrub
    port map(
        clk => std_logic(clk_i),

        -- ---- CPU transactions (DMEM port A) ----
        probe0 => cpu_rw_slv,                   -- CPU read/write: '1' = write
        probe1 => std_logic_vector(cpu_ben_i),  -- CPU byte enables, nonzero = active transaction
        probe2 => std_logic_vector(cpu_addr_i), -- CPU byte address being accessed
        probe3 => std_logic_vector(cpu_data_i), -- CPU write data word

        -- ---- Scrubber transactions (DMEM port B) ----
        probe4 => scrub_en_slv,                  -- scrubber port b transaction enable
        probe5 => scrub_rw_slv,                  -- scrubber read/write: '1' = writeback
        probe6 => std_logic_vector(scrub_wdata), -- scrubber writeback data (corrected word)
        probe7 => std_logic_vector(scrub_rdata), -- data read from DMEM by the scrubber

        -- ---- FSM internals ----
        probe8  => std_logic_vector(stat_state_o), -- FSM state (encoded), shows the scrub cycle
        probe9  => std_logic_vector(stat_addr_o),  -- scrubber pointer as a byte address
        probe10 => stat_busy_slv,                  -- '1' = scrubber active (not in idle)
        probe11 => stat_full_pass_slv,             -- pulses '1' at the end of a full revolution

        -- ---- Error / conflict events (use as triggers, rising edge) ----
        probe12 => stat_corrected_slv,             -- single-bit error corrected this word
        probe13 => stat_detected_slv,              -- uncorrectable (double-bit) error this word
        probe14 => stat_data_valid_slv,            -- word checked and found valid
        probe15 => std_logic_vector(flog_count_o), -- running count of logged (unfixable) errors
        probe16 => stat_conflict_slv               -- conflict (cpu writing at same addr as scrubber)
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