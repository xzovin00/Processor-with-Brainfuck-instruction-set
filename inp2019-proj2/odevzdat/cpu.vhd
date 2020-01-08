-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
--
-- Author : Martin Žovinec 
-- Login :  xzovin00
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------

architecture behavioral of cpu is


----------------------------------------------------
-- Programovy citac

signal pc_output : std_logic_vector(11 downto 0);
signal pc_inc : std_logic; 
signal pc_dec : std_logic;


----------------------------------------------------
-- Ukazatelovy citac

signal ptr_output: std_logic_vector(11 downto 0);
signal ptr_inc : std_logic;
signal ptr_dec : std_logic;
signal mx2_output : std_logic_vector (11 downto 0);


----------------------------------------------------
-- While citac

signal cnt_output : std_logic_vector(7 downto 0);
signal cnt_inc : std_logic;
signal cnt_dec : std_logic;


----------------------------------------------------
-- Selekty pro multiplexory

signal sel1 : std_logic;
signal sel2 : std_logic;
signal sel3 : std_logic_vector(1 downto 0);


----------------------------------------------------
-- Stavy

type state is (
   start, 
   load,
   decode,
   val_inc1, val_inc2,            -- +
   val_dec1, val_dec2,            -- -
   s_ptr_inc, s_ptr_dec,          -- >  <
   put1, put2,                    -- ,
   get1, get2,                    -- .
   swhile1, swhile2, swhile3, swhile4, swhile5,    -- [
   ewhile1, ewhile2, ewhile3, ewhile4, ewhile5,  -- ]
   copy1, copy2,                  -- $
   paste1, paste2,                -- !
   halt,                          -- null
   other

);

signal pstate : state;
signal nstate : state;

-- ------------------------------------------------------------------------------
--                               Datova cast
-- ------------------------------------------------------------------------------

begin


--------------------------------------------------------------------------------
--    Address of instructions in RAM

Program_address_counter: process (RESET, CLK)
begin
   if (RESET = '1') then 
      pc_output <= (others => '0');
   elsif (CLK'event) and (CLK='1') then
      if (pc_inc = '1') then
         pc_output <= pc_output + 1;
      elsif (pc_dec = '1') then
         pc_output <= pc_output - 1;
      end if;
   end if;
end process;




--------------------------------------------------------------------------------
--    Address of data in RAM

Data_address_counter: process (RESET, CLK)
begin
   if (RESET = '1') then 
      ptr_output <= (others => '0');
   elsif (CLK'event) and (CLK='1') then
      if (ptr_inc = '1') then
         ptr_output <= ptr_output + 1;
      elsif (ptr_dec = '1') then
         ptr_output <= ptr_output - 1;
      end if;
   end if;
end process;




--------------------------------------------------------------------------------
--    While counter

While_counter: process (RESET, CLK)
begin
   if (RESET = '1') then 
      cnt_output <= (others => '0');
   elsif (CLK'event) and (CLK='1') then
      if (cnt_inc = '1') then
         cnt_output <= cnt_output + 1;
      elsif (cnt_dec = '1') then
         cnt_output <= cnt_output - 1;
      end if;
   end if;
end process;




--------------------------------------------------------------------------------
-- Multiplexor 1

Multiplexor1: process(sel1,  pc_output , mx2_output)   
begin
   case sel1 is
      when '0' => DATA_ADDR <= '0' & pc_output;
      when others  => DATA_ADDR <= '1' & mx2_output;
   end case;
end process;




--------------------------------------------------------------------------------
-- Multiplexor 2

Multiplexor2: process(sel2, ptr_output)    
begin
   case sel2 is
      when '0' => mx2_output <= ptr_output;
      when others  => mx2_output <= X"000";
   end case;
end process;




--------------------------------------------------------------------------------
-- Multiplexor 3

Multiplexor3: process(sel3, DATA_RDATA, IN_DATA)
begin
   case sel3 is
      when "00" => DATA_WDATA <= IN_DATA;
      when "01" => DATA_WDATA <= DATA_RDATA - 1;
      when "10" => DATA_WDATA <= DATA_RDATA + 1;
      when others  => DATA_WDATA <= DATA_RDATA;
   end case;
end process;





--------------------------------------------------------------------------------
-- Zpracovani pstate 

Pstate_proces: process(RESET, CLK)
begin
   if (RESET = '1') then
      pstate <= start;
   elsif (CLK'event) and (CLK = '1') then
      if (EN = '1') then
         pstate <= nstate;
      end if;
   end if;
end process;




-- ------------------------------------------------------------------------------
--                                 Automat
-- ------------------------------------------------------------------------------

Automat: process(IN_VLD, IN_DATA, DATA_RDATA, OUT_BUSY, pstate, cnt_output)
begin

   ----------------------------------------------------
   -- Default values

   DATA_EN  <= '0';
   DATA_RDWR  <=  '0';

   IN_REQ  <= '0';
   OUT_WE  <= '0';
   OUT_DATA <= X"00";

   pc_inc  <= '0';
   pc_dec  <= '0';
   ptr_inc  <=  '0';
   ptr_dec  <= '0';
   cnt_inc  <=  '0';
   cnt_dec  <=  '0';

   sel1  <=  '0';
   sel2  <=  '0';
   sel3 <= "11";



   case pstate is


      ----------------------------------------------------
      -- start

      when start  => 
         nstate  <= load;


      ----------------------------------------------------
      -- load

      when load  => 
         nstate  <= decode;

         -- vyber aktualni instrukcni adresu
         sel1  <= '0';
         
         -- nastavi RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';

      ----------------------------------------------------
      -- Dekodovani instrukci

      when decode  => 
         case (DATA_RDATA) is
            when X"3E" => nstate <= s_ptr_inc;    -- >
            when X"3C" => nstate <= s_ptr_dec;    -- <
            when X"2B" => nstate <= val_inc1;     -- +
            when X"2D" => nstate <= val_dec1;     -- -
            when X"5B" => nstate <= swhile1;       -- [
            when X"5D" => nstate <= ewhile1;      -- ]
            when X"2E" => nstate <= put1;         -- .
            when X"2C" => nstate <= get1;         -- ,
            when X"24" => nstate <= copy1;         -- $
            when X"21" => nstate <= paste1;        -- !
            when X"00" => nstate <= halt;         -- null
            when others=> nstate <= other;        -- other
         end case;


      ----------------------------------------------------
      -- Zvyseni ukazatele adres o jedna     (>)

      when s_ptr_inc =>
         nstate <= load;
         pc_inc <= '1';

         ptr_inc <= '1';


      ----------------------------------------------------
      -- Snizeni ukazatele adres o jedna     (<)

      when s_ptr_dec =>
         nstate <= load;
         pc_inc <= '1';

         ptr_dec <= '1';


      ----------------------------------------------------
      -- Zvyseni hodnoty na adrese o jedna   (+)

      when val_inc1  => 
         nstate  <=  val_inc2;
         pc_inc  <= '1';

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';

      when val_inc2  => 
         nstate  <= load;

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- inkrementuj hodnotu
         sel3  <= "10";

         -- nastav RAM na zapis
         DATA_EN  <= '1';
         DATA_RDWR  <=  '1';


      ----------------------------------------------------
      -- Snizeni hodnoty na adrese o jedna   (-)

      when val_dec1  => 
         nstate  <=  val_dec2;
         pc_inc  <= '1';

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';


      when val_dec2  => 
         nstate  <= load;

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- dekrementuj hodnotu
         sel3  <= "01";

         -- nastav RAM na zapis
         DATA_EN  <= '1';
         DATA_RDWR  <=  '1';


      ----------------------------------------------------
      -- Vytisk hodnoty aktualni bunky       (.)

      when put1  => 
         nstate  <=  put2;
         pc_inc  <= '1';

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';


      when put2  => 

         -- instrukce je zacyklena dokud je displej zaneprazdnen
         if (OUT_BUSY = '0') then
            nstate  <= load;

            -- vytisknuti na displej
            OUT_WE  <=  '1';
            OUT_DATA <= DATA_RDATA;
         else
            nstate  <= put2;
         end if;

      ----------------------------------------------------
      -- Nacteni hodnoty od uzivatele     (,)

      --when get1  => 
         --nstate  <=  get2;
         --pc_inc  <= '1';

         --IN_REQ  <= '1';
      when get1  => 
         nstate  <= get1;

         -- instrukce je zacyklena dokud neprijde validni vstup
         if (IN_VLD = '1') then
            nstate  <= load;
            pc_inc  <= '1';

            -- vyber aktualni data adresu
            sel2  <= '0';
            sel1  <= '1';

            -- nastavi zapis IN_DATA do DATA_WDATA
            sel3  <=  "00";

            -- nastavi RAM na zapis
            DATA_EN  <= '1';
            DATA_RDWR  <=  '1';
         else
            IN_REQ  <= '1';
         end if;


      ----------------------------------------------------
      -- Ulozeni aktualni bunky do pomocne promene   ($)

      when copy1  => 
         nstate  <=  copy2;
         pc_inc  <= '1';

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';

      when copy2  => 
         nstate  <= load;

         -- vyber adresu pomocne promene
         sel2  <= '1';
         sel1  <= '1';

         -- uloz aktualni hodnotu
         sel3  <= "11";

         -- nastav RAM na zapis
         DATA_EN  <= '1';
         DATA_RDWR  <=  '1';



      ----------------------------------------------------
      -- Nacteni ulozene hodnoty z pomocne bunky do aktualni bunky   (!)

      when paste1  => 
         nstate  <=  paste2;
         pc_inc  <= '1';

         -- vyber adresu pomocne promene
         sel2  <= '1';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';

      when paste2  => 
         nstate  <= load;

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- uloz aktualni hodnotu
         sel3  <= "11";

         -- nastav RAM na zapis
         DATA_EN  <= '1';
         DATA_RDWR  <=  '1';


      ----------------------------------------------------
      -- Zacatek cyklu           ( [ )

      when swhile1  => 
         nstate  <= swhile2;
         pc_inc  <= '1';

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';

      when swhile2  => 

         -- pokud v aktualni bunce neni nula program se vykonava do ]
         if (DATA_RDATA  /= X"00") then
            nstate  <= load;

         -- jinak se instrukce po ] ignoruji
         else
            nstate  <= swhile3;

            -- zvis pocet zanoreni cyklu o jedna
            cnt_inc  <= '1';

            -- vyber instrukci
            sel1  <= '0';

            -- nastav RAM na cteni
            DATA_EN  <= '1';
            DATA_RDWR  <= '0';


         end if;
      when swhile3  => 
         nstate  <= swhile4;

         -- vyber instrukci
         sel1  <= '0';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <= '0';

      when swhile4  => 
         nstate  <= swhile5;

         -- pokud narazime na konec cyklu ( ] ), pocet zanoreni se snizi
         if (DATA_RDATA = X"5D") then -- ]
            cnt_dec  <= '1';

         -- pokud narazime na zacatek cyklu ( [ ), pocet zanoreni se zvysi
         elsif (DATA_RDATA = X"5B") then -- [
            cnt_inc  <= '1';
         end if;

      when swhile5  => 
         pc_inc  <= '1';

         -- cyklus pokracuje dokud pocet zanoreni neni roven nule
         if (cnt_output = X"00") then           
            nstate  <= load;
         else
            nstate  <= swhile3;

         end if;
      ----------------------------------------------------
      -- Ukonceni cyklu           ( [ )

      when ewhile1  => 
         nstate  <= ewhile2;

         -- vyber aktualni data adresu
         sel2  <= '0';
         sel1  <= '1';

         -- nastav RAM na cteni
         DATA_EN  <= '1';
         DATA_RDWR  <=  '0';

      when ewhile2  => 

         -- pokud v aktualni bunce je nula tak cyklus konci
         if (DATA_RDATA  = X"00") then
            nstate  <= load;
            pc_inc  <= '1';

         -- jinak se program vraci k odpovidajici [
         else
            nstate  <= ewhile3;

            -- posuneme se o instrukci zpet
            pc_dec  <= '1';
            -- zvis pocet zanoreni cyklu o jedna
            cnt_inc  <= '1';

         end if;

      when ewhile3  => 
         nstate  <=  ewhile4;
            -- vyber instrukci
            sel1  <= '0';

            -- nastav RAM na cteni
            DATA_EN  <= '1';
            DATA_RDWR  <= '0';

      when ewhile4  => 
         nstate  <=  ewhile5;

         -- pokud narazime na konec cyklu ( ] ), pocet zanoreni se zvysi
         if (DATA_RDATA = X"5D") then -- ]
            cnt_inc  <= '1';

         -- pokud narazime na zacatek cyklu ( [ ), pocet zanoreni se snizi
         elsif (DATA_RDATA = X"5B") then -- [
            cnt_dec  <= '1';
         end if;

      when ewhile5  => 
         -- cyklus pokracuje dokud pocet zanoreni neni roven nule
         if (cnt_output = X"00") then  
            nstate  <=  load;
            pc_inc  <= '1';
         else
            nstate  <= ewhile3;
            pc_dec  <= '1';
         end if;



      ----------------------------------------------------
      -- Ukonceni Programu, program se zacykli a dal se uz nic nedeje (null)

      when halt  => 
         nstate  <= halt;


      ----------------------------------------------------
      -- Ostatni vstup se ignoruje (pismena atd.)


      when other  => 
         nstate  <= load;
         pc_inc  <= '1';


      ----------------------------------------------------
      -- Neosetrene stavy ( i kdyz jsou vsechny osetrene v dekodovani )

      when others =>
         null;

   end case;


 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.

end process;
end behavioral;
 
