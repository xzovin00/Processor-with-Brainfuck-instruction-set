-- ram.vhd : 8kB RAM memory
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Zdenek Vasicek <vasicek AT fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 
use IEEE.std_logic_ARITH.ALL;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity ram is
 generic (
   INIT  : string := ""
 );
 port (
   CLK   : in std_logic; -- hodiny

   ADDR  : in std_logic_vector(12 downto 0);  -- adresa bunky
   WDATA : in std_logic_vector(7 downto 0);  -- data pro zapis
   RDATA : out std_logic_vector(7 downto 0); -- nactena data (v dalsim taktu, pokud EN=1)
   RDWR  : in std_logic;                     -- 0 - cteni, 1 - zapis
   EN    : in std_logic                      -- 1 - povoleni prace s pameti
 );
end ram;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of ram is

   type t_ram is array (0 to 2**13-1) of std_logic_vector (7 downto 0);

   function str2vec(arg: string) return t_ram is
      variable result: t_ram := (others => (others => '0'));
    begin
      for i in arg'range loop
          result(i-1) := conv_std_logic_vector(character'pos(arg(i)), 8);
      end loop;
      return result;
    end; 
   
   signal ram: t_ram := str2vec(INIT);
   signal rd : std_logic_vector (7 downto 0) := (others => '0');
begin
   RDATA <= rd;
   
   -- RAM rd / wr
   sram_mem: process (CLK)
   begin
      if (CLK'event) and (CLK = '1') then
         if (EN = '1') then
            if (RDWR = '1') then
               ram(conv_integer(ADDR)) <= WDATA;
               rd <= WDATA;
            else
               rd <= ram(conv_integer(ADDR));
            end if;
         end if;
      end if;
   end process;
   
end behavioral;

