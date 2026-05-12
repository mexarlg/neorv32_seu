--==============================================================================
--  Package:       seu_pkg
--  Project:       Neorv32_SEU
--  Author:        Olivier Oribes
--  Created:       10/05/2026
--  Last Modified: 10/05/2026
--
--  Description:
--  Package containing types, constants, and component declarations
--  for the module.
--
--==============================================================================

library ieee;
use ieee.std_logic_1164.all;

package seu_pkg is

  function fibo_lfsr(seed : std_ulogic_vector(31 downto 0))
    return std_ulogic_vector;

end package seu_pkg;

package body seu_pkg is

  function fibo_lfsr(seed : std_ulogic_vector(31 downto 0))
    return std_ulogic_vector is
    variable s : std_ulogic_vector(31 downto 0) := seed;
    variable b : std_ulogic;
  begin
    b := s(31) xor s(21) xor s(1) xor s(0);
    s := b & s(31 downto 1);
    return s;
  end function;

end package body seu_pkg;

