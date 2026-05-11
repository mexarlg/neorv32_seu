-- ================================================================================ --
-- NEORV32 SoC - Single Error Correction Double Error Detection (SECDED) Encoder    --
-- -------------------------------------------------------------------------------- --
--      Combinational SECDED encoder for 32-bit data words                          --
--      Generates 7 check bits using the same H matrix as secded_decoder            --
--      Matrix H should be common to both encoder and decoder                       --
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

entity neorv32_secded_encoder is
    port (
        -- 32 bit data to be written in memory (encoded)
        data_i : in std_ulogic_vector(31 downto 0);
        -- 7 bit SecDed check (1 bit fix, 2 bit detection)
        secded_o : out std_ulogic_vector(6 downto 0)
    );
end entity neorv32_secded_encoder;

architecture comb of neorv32_secded_encoder is

    -- H matrix, 32 rows (data), 7 columns (secded)
    type h_column_t is array (0 to 31) of std_ulogic_vector(6 downto 0);

    -- A 1 defines a xor dependency between a data bit to each bit of the secded code
    constant H_DATA : h_column_t := (
        0  => "0000111",
        1  => "0001011",
        2  => "0001101",
        3  => "0001110",
        4  => "0010011",
        5  => "0010101",
        6  => "0010110",
        7  => "0011001",
        8  => "0011010",
        9  => "0011100",
        10 => "0100011",
        11 => "0100101",
        12 => "0100110",
        13 => "0101001",
        14 => "0101010",
        15 => "0101100",
        16 => "0110001",
        17 => "0110010",
        18 => "0110100",
        19 => "0111000",
        20 => "1000011",
        21 => "1000101",
        22 => "1000110",
        23 => "1001001",
        24 => "1001010",
        25 => "1001100",
        26 => "1010001",
        27 => "1010010",
        28 => "1010100",
        29 => "1011000",
        30 => "1100001",
        31 => "1100010"
    );

begin

    -- secded_o(j) = secded_o(j) XOR data_i(i) if H_DATA(i)(j) = 1
    encode_proc : process (data_i)
        variable secded : std_ulogic_vector(6 downto 0);
    begin
        secded := (others => '0');
        for i in 0 to 31 loop
            -- for each bit of a data
            for j in 0 to 6 loop
                -- xor the secded and the whole data if matrix pos value = 1
                if H_DATA(i)(j) = '1' then
                    secded(j) := secded(j) xor data_i(i);
                end if;
            end loop;
        end loop;
        secded_o <= secded;
    end process encode_proc;
end architecture comb;