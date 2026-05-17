-- ================================================================================ --
-- NEORV32 SoC - Single Error Correction Double Error Detection (SECDED) Decoder    --
-- -------------------------------------------------------------------------------- --
--      Combinational SEC-DED (Single Error Correction, Double Error Detection)     --
--      decoder for 32-bit data words with 7 check bits (39 bit codeword)           --
--                                                                                  --
--      Uses a Hsiao style parity matrix where every data column has odd            --
--      weight (3 ones), enabling single/double error distinction through           --
--      codeword parity                                                             --
--                                                                                  --
--      Author: Aldo Lupio - 2026                                                   --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;

entity neorv32_secded_decoder is
    port (
        -- Inputs to check (decode)
        data_i  : in std_ulogic_vector(31 downto 0);
        check_i : in std_ulogic_vector(6 downto 0);
        -- Output corrected data
        data_o : out std_ulogic_vector(31 downto 0);
        -- Status of correction
        stat_corrected_o  : out std_ulogic;
        stat_detected_o   : out std_ulogic;
        stat_data_valid_o : out std_ulogic
    );
end entity neorv32_secded_decoder;

architecture comb of neorv32_secded_decoder is

    -- H matrix, 32 rows (data), 7 columns (secded)
    type h_column_t is array (0 to 31) of std_ulogic_vector(6 downto 0);

    -- A 1 defines a xor dependency between a data bit to each bit of the secded code
    -- Secded code: c6 c5 c4 c3 c2 c1 c0
    constant H_DATA : h_column_t := (
        0  => "0000111", -- d0  : c0, c1, c2
        1  => "0001011", -- d1  : c0, c1, c3
        2  => "0001101", -- d2  : c0, c2, c3
        3  => "0001110", -- d3  : c1, c2, c3
        4  => "0010011", -- d4  : c0, c1, c4
        5  => "0010101", -- d5  : c0, c2, c4
        6  => "0010110", -- d6  : c1, c2, c4
        7  => "0011001", -- d7  : c0, c3, c4
        8  => "0011010", -- d8  : c1, c3, c4
        9  => "0011100", -- d9  : c2, c3, c4
        10 => "0100011", -- d10 : c0, c1, c5
        11 => "0100101", -- d11 : c0, c2, c5
        12 => "0100110", -- d12 : c1, c2, c5
        13 => "0101001", -- d13 : c0, c3, c5
        14 => "0101010", -- d14 : c1, c3, c5
        15 => "0101100", -- d15 : c2, c3, c5
        16 => "0110001", -- d16 : c0, c4, c5
        17 => "0110010", -- d17 : c1, c4, c5
        18 => "0110100", -- d18 : c2, c4, c5
        19 => "0111000", -- d19 : c3, c4, c5
        20 => "1000011", -- d20 : c0, c1, c6
        21 => "1000101", -- d21 : c0, c2, c6
        22 => "1000110", -- d22 : c1, c2, c6
        23 => "1001001", -- d23 : c0, c3, c6
        24 => "1001010", -- d24 : c1, c3, c6
        25 => "1001100", -- d25 : c2, c3, c6
        26 => "1010001", -- d26 : c0, c4, c6
        27 => "1010010", -- d27 : c1, c4, c6
        28 => "1010100", -- d28 : c2, c4, c6
        29 => "1011000", -- d29 : c3, c4, c6
        30 => "1100001", -- d30 : c0, c5, c6
        31 => "1100010"  -- d31 : c1, c5, c6
    );

    -- secded decoded from data (valid if 0s)
    signal syndrome : std_ulogic_vector(6 downto 0);
    -- parity computed from data and secded code
    signal parity_all : std_ulogic;

begin

    -- syndrome(j) = check_i(j) XOR data_i(i) if H_DATA(i)(j) = 1
    syndrome_gen : process (data_i, check_i)
        variable s : std_ulogic_vector(6 downto 0);
    begin
        s := check_i;
        for i in 0 to 31 loop
            for j in 0 to 6 loop
                if H_DATA(i)(j) = '1' then
                    s(j) := s(j) xor data_i(i);
                end if;
            end loop;
        end loop;
        syndrome <= s;
    end process syndrome_gen;

    -- Parity odd = single bit error, Parity even = double bit error or no error
    parity_gen : process (data_i, check_i)
        variable p : std_ulogic;
    begin
        p := '0';
        for i in 0 to 31 loop
            p := p xor data_i(i);
        end loop;
        for i in 0 to 6 loop
            p := p xor check_i(i);
        end loop;
        parity_all <= p;
    end process parity_gen;

    -- Status outcomes:
    decode_proc : process (data_i, syndrome, parity_all)
        variable data_fixed : std_ulogic_vector(31 downto 0);
    begin
        data_fixed := data_i;
        stat_data_valid_o <= '0';
        stat_corrected_o  <= '0';
        stat_detected_o   <= '0';

        if syndrome = "0000000" then
            -- syndrome match, data valid
            stat_data_valid_o <= '1';

        elsif parity_all = '1' then
            -- syndrome mismatch, parity changed once, error fixable
            for i in 0 to 31 loop
                if syndrome = H_DATA(i) then
                    data_fixed(i) := not data_fixed(i);
                end if;
            end loop;
            stat_corrected_o <= '1';

        else
            -- syndrome mismatch and parity changed twice, error detected but data is not valid
            stat_detected_o <= '1';

        end if;

        data_o <= data_fixed;
    end process decode_proc;

end architecture comb;