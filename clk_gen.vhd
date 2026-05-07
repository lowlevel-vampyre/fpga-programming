-- LATTICE FPGA MODULE -- PLL
--
-- -- CLKI:
--      Input Freq = 8.31mhz
--      Input divider = 1
--
-- -- CLKFB
--      FBK Mode = INT_OP
--      no fractiuonal divider
--
-- -- CLKOP
--      Desired Freq = 25mhz
--      Tolerance = 1.0
--      divider = 21
--      actaul freq = 24.930000
--
-- -- Optional Port Selections
--      n/a
--
-- -- PLL Reset Options
--      n/a
--
-- -- Lock Settings:
--      Enable provide PLL Lock Signal
--      PLL lock is sticky



-- ============================================================================
-- ============================================================================
-- ===================  MODULE 1: Clock and Reset Generator  ==================
-- ============================================================================
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity clk_gen is
    port (
        clk_out : out std_logic;
        rst_out : out std_logic
    );
end entity clk_gen;

architecture behavioral of clk_gen is

    signal osc_clk      : std_logic;
	signal pll_out_clk      : std_logic;
    signal pll_lock     : std_logic;
    signal rst_cnt      : integer range 0 to 65535 := 0;


    component OSCJ
        generic ( NOM_FREQ : string := "8.31" );
        port (
            STDBY    : in  std_logic;
            OSC      : out std_logic;
            SEDSTDBY : out std_logic
        );
    end component;

    component PLL_CLK
        port (
            CLKI  : in  std_logic;
            CLKOP : out std_logic;
            LOCK  : out std_logic
        );
    end component;

begin

    osc_inst : OSCJ
        generic map ( NOM_FREQ => "8.31" )
        port map (
            STDBY    => '0',
            OSC      => osc_clk,
            SEDSTDBY => open
        );

    pll_inst : PLL_CLK
        port map (
            CLKI  => osc_clk,
            CLKOP => pll_out_clk,
            LOCK  => pll_lock
        );

	-- ============================================================
    -- 3) Output assignment (clean separation)
    -- ============================================================
    clk_out <= pll_out_clk;

    process(pll_out_clk)
    begin
        if rising_edge(pll_out_clk) then
            if pll_lock = '0' then
                rst_cnt <= 0;
                rst_out <= '1';
            elsif rst_cnt < 65535 then
                rst_cnt <= rst_cnt + 1;
                rst_out <= '1';
            else
                rst_out <= '0';
            end if;
        end if;
    end process;

end architecture behavioral;
