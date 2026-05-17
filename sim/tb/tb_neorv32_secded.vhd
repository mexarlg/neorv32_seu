-- ==============================================================================
--  Testbench   : tb_neorv32_secded
--  File        : tb_neorv32_secded.vhd
--
--  DUT         : neorv32_secded_encoder.vhd
--  DUT         : neorv32_secded_decoder.vhd
--
--  Description :
--      Verifies encoder/decoder pair through four phases:
--        1. Clean data (no error, encoder to decoder roundtrip)
--        2. Single bit errors on data bits (correction)
--        3. Single bit errors on check bits (detection, no data change)
--        4. Double bit errors on data bits (detection, uncorrectable)
--
--  Author: Aldo Lupio
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_neorv32_secded is
end entity tb_neorv32_secded;

architecture sim of tb_neorv32_secded is

    -- Encoder signals
    signal secded_enc_data_i : std_ulogic_vector(31 downto 0) := (others => '0');
    signal secded_enc_code_o : std_ulogic_vector(6 downto 0)  := (others => '0');

    -- Decoder signals
    signal secded_dec_data_i        : std_ulogic_vector(31 downto 0) := (others => '0');
    signal secded_dec_code_i        : std_ulogic_vector(6 downto 0)  := (others => '0');
    signal secded_dec_data_o        : std_ulogic_vector(31 downto 0) := (others => '0');
    signal secded_stat_corrected_o  : std_ulogic                     := '0';
    signal secded_stat_detected_o   : std_ulogic                     := '0';
    signal secded_stat_data_valid_o : std_ulogic                     := '0';

    -- Simulation control
    signal sim_done    : boolean := false;
    signal test_phase  : natural := 0;
    signal error_count : natural := 0;

    -- Settling time for combinational logic
    constant T_PROP : time := 10 ns;

    -- Test data patterns
    type test_data_t is array (natural range <>) of std_ulogic_vector(31 downto 0);
    constant TEST_WORDS : test_data_t := (
        x"00000000",
        x"FFFFFFFF",
        x"DEADBEEF",
        x"A5A5A5A5",
        x"00000001",
        x"80000000",
        x"12345678"
    );

    -- Assertion helper
    procedure check(
        condition : in boolean;
        msg       : in string;
        err_count : inout natural
    ) is
    begin
        if not condition then
            report "FAIL: " & msg severity error;
            err_count := err_count + 1;
        end if;
    end procedure;

begin

    -- DUT: Encoder (Computes Secded code given data)
    dut_encoder : entity work.neorv32_secded_encoder
        port map(
            data_i   => secded_enc_data_i,
            secded_o => secded_enc_code_o
        );

    -- DUT: Decoder (Checks given data and Secded code accord)
    dut_decoder : entity work.neorv32_secded_decoder
        port map(
            data_i            => secded_dec_data_i,
            check_i           => secded_dec_code_i,
            data_o            => secded_dec_data_o,
            stat_corrected_o  => secded_stat_corrected_o,
            stat_detected_o   => secded_stat_detected_o,
            stat_data_valid_o => secded_stat_data_valid_o
        );

    -- Stimulus ---------------------------------------------------------------
    p_stim : process
        variable v_code     : std_ulogic_vector(6 downto 0);
        variable v_bad_data : std_ulogic_vector(31 downto 0);
        variable v_bad_code : std_logic_vector(6 downto 0);
        variable v_errors   : natural := 0;
    begin

        --------------------------------------------------------------------
        -- Phase 1: Clean data (data should be valid)
        --------------------------------------------------------------------
        test_phase <= 1;
        report "Phase 1: Clean data (no errors)" severity note;

        for idx in TEST_WORDS'range loop

            -- Encode
            secded_enc_data_i <= TEST_WORDS(idx);
            wait for T_PROP;
            v_code := secded_enc_code_o;

            -- Decode with clean data and matching code
            secded_dec_data_i <= TEST_WORDS(idx);
            secded_dec_code_i <= std_ulogic_vector(v_code);
            wait for T_PROP;

            check(secded_stat_data_valid_o = '1', "no_error should be 1 for clean word " & integer'image(idx), v_errors);
            check(secded_stat_corrected_o = '0', "corrected should be 0 for clean word " & integer'image(idx), v_errors);
            check(secded_stat_detected_o = '0', "detected should be 0 for clean word " & integer'image(idx), v_errors);
            check(secded_dec_data_o = TEST_WORDS(idx), "data_o mismatch for clean word " & integer'image(idx), v_errors);

        end loop;

        report "Phase 1 complete" severity note;

        --------------------------------------------------------------------
        -- Phase 2: Single bit errors on data (data should be valid)
        --------------------------------------------------------------------
        test_phase <= 2;
        report "Phase 2: Single bit errors on data (all 32 positions)" severity note;

        for idx in TEST_WORDS'range loop

            -- Encode clean data
            secded_enc_data_i <= TEST_WORDS(idx);
            wait for T_PROP;
            v_code := secded_enc_code_o;

            -- Flip each data bit one at a time
            for bit_pos in 0 to 31 loop

                -- Flip bit of data
                v_bad_data          := TEST_WORDS(idx);
                v_bad_data(bit_pos) := not v_bad_data(bit_pos);

                -- Input bad data to decoder
                secded_dec_data_i <= v_bad_data;
                secded_dec_code_i <= std_logic_vector(v_code);
                wait for T_PROP;

                -- Check outputs
                check(secded_stat_corrected_o = '1',
                "corrected should be 1 for word " & integer'image(idx) &
                " bit " & integer'image(bit_pos), v_errors);
                check(secded_stat_data_valid_o = '0',
                "no_error should be 0 for word " & integer'image(idx) &
                " bit " & integer'image(bit_pos), v_errors);
                check(secded_stat_detected_o = '0',
                "detected should be 0 for single-bit error word " & integer'image(idx) &
                " bit " & integer'image(bit_pos), v_errors);
                check(secded_dec_data_o = TEST_WORDS(idx),
                "data_o should match original for word " & integer'image(idx) &
                " bit " & integer'image(bit_pos), v_errors);

            end loop;
        end loop;

        report "Phase 2 complete" severity note;

        --------------------------------------------------------------------
        -- Phase 3: Single bit errors on secded code (data should be valid)
        --------------------------------------------------------------------
        test_phase <= 3;
        report "Phase 3: Single bit errors on secded code (all 7 positions)" severity note;

        for idx in TEST_WORDS'range loop

            -- Encode clean data
            secded_enc_data_i <= TEST_WORDS(idx);
            wait for T_PROP;
            v_code := secded_enc_code_o;

            -- Flip each check bit one at a time
            for bit_pos in 0 to 6 loop

                -- Flip bit of seceded
                v_bad_code          := std_logic_vector(v_code);
                v_bad_code(bit_pos) := not v_bad_code(bit_pos);

                -- Input bad secded onto decoder
                secded_dec_data_i <= TEST_WORDS(idx);
                secded_dec_code_i <= v_bad_code;
                wait for T_PROP;

                -- check
                check(secded_stat_corrected_o = '1',
                "corrected should be 1 for check bit " & integer'image(bit_pos) &
                " word " & integer'image(idx), v_errors);
                check(secded_dec_data_o = TEST_WORDS(idx),
                "data_o should be unchanged for check bit error word " & integer'image(idx) &
                " bit " & integer'image(bit_pos), v_errors);

            end loop;
        end loop;

        report "Phase 3 complete" severity note;

        --------------------------------------------------------------------
        -- Phase 4: Double bit errors on data (detectable only)
        --------------------------------------------------------------------
        test_phase <= 4;
        report "Phase 4: Double bit errors on data (uncorrectable)" severity note;

        for idx in TEST_WORDS'range loop

            -- Encode clean data
            secded_enc_data_i <= TEST_WORDS(idx);
            wait for T_PROP;
            v_code := secded_enc_code_o;

            -- Flip bit pairs: (0,1), (5,10), (15,31), (0,31)
            for pair in 0 to 3 loop

                v_bad_data := TEST_WORDS(idx);

                -- Flip 2 bits
                case pair is
                    when 0 => v_bad_data(0)  := not v_bad_data(0);
                        v_bad_data(1)            := not v_bad_data(1);
                    when 1 => v_bad_data(5)  := not v_bad_data(5);
                        v_bad_data(10)           := not v_bad_data(10);
                    when 2 => v_bad_data(15) := not v_bad_data(15);
                        v_bad_data(31)           := not v_bad_data(31);
                    when 3 => v_bad_data(0)  := not v_bad_data(0);
                        v_bad_data(31)           := not v_bad_data(31);
                    when others => null;
                end case;

                -- Input to encoder
                secded_dec_data_i <= v_bad_data;
                secded_dec_code_i <= std_logic_vector(v_code);
                wait for T_PROP;

                -- check
                check(secded_stat_detected_o = '1',
                "detected should be 1 for double error word " & integer'image(idx) &
                " pair " & integer'image(pair), v_errors);
                check(secded_stat_corrected_o = '0',
                "corrected should be 0 for double error word " & integer'image(idx) &
                " pair " & integer'image(pair), v_errors);
                check(secded_stat_data_valid_o = '0',
                "no_error should be 0 for double error word " & integer'image(idx) &
                " pair " & integer'image(pair), v_errors);

            end loop;
        end loop;

        report "Phase 4 complete" severity note;

        --------------------------------------------------------------------
        -- Results
        --------------------------------------------------------------------
        test_phase  <= 0;
        error_count <= v_errors;
        wait for T_PROP;

        report "========================================" severity note;
        if v_errors = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report "TESTS FAILED: " & integer'image(v_errors) & " errors" severity error;
        end if;
        report "========================================" severity note;

        sim_done <= true;
        wait;
    end process p_stim;
end architecture sim;