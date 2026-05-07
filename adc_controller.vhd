library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adc_controller is
    port (
        -- clock
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- SPI interface to ADC
        SPI_clk     : out std_logic;
        SPI_MOSI     : out std_logic;  -- MOSI
        SPI_MISO    : in  std_logic;  -- MISO
        SPI_CSn     : out std_logic;

        -- bus interface
        bus_data    : out std_logic_vector(15 downto 0);
        bus_addr    : out std_logic_vector(15 downto 0);
        bus_cmd     : out std_logic;
        bus_rqst    : out std_logic;
        bus_enable  : in  std_logic
    );
end entity adc_controller;

architecture behavioral of adc_controller is

    type state_type is (
        IDLE,
        DUMMY_CMD,
        LOAD_CMD,
        SAMPLE,
        ISSUE_BUS,
        RESET_VALUES
    );

    signal state, next_state : state_type;

    signal cmd_reg      : std_logic_vector(15 downto 0);
    signal shift_out    : std_logic_vector(15 downto 0);
    signal shift_in     : std_logic_vector(15 downto 0);

    signal sync_counter : integer range 0 to 65535;
    signal bit_cnt      : integer range 0 to 15;

	signal dummy_sent 	: integer range 0 to 1;

    -- SPI clock divider
    signal spi_div      : integer range 0 to 255;
    signal spi_clk_int  : std_logic;

    -- FIX: edge detection signals — lets us stay in one clock domain
    -- instead of clocking processes off spi_clk_int directly
    signal spi_clk_prev : std_logic;
    signal spi_rise     : std_logic;  -- single sys-clk pulse on SPI rising edge
    signal spi_fall     : std_logic;  -- single sys-clk pulse on SPI falling edge

	signal address       : integer range 0 to 65535;
    constant DIV_MAX    : integer := 2;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
            else
                state <= next_state;
            end if;
        end if;
    end process;

    -- =========================================================
    -- SPI clock divider
    -- Generates spi_clk_int by toggling every DIV_MAX x 40.11 ns
    -- currently tuned to 24.97 / 6  = 4.16 MHz
    -- spi_clk_int is an internal signal only that drives the SPI_clk
    -- -output port as a wire. No process is clocked off it.
    -- =========================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                spi_div     <= 0;
                spi_clk_int <= '0';
                spi_clk_prev <= '0';
            else
                spi_clk_prev <= spi_clk_int;  -- capture previous value for edge detect

                if spi_div = DIV_MAX then
                    spi_div     <= 0;
                    spi_clk_int <= not spi_clk_int;
                else
                    spi_div <= spi_div + 1;
                end if;
            end if;
        end if;
    end process;

    SPI_clk <= spi_clk_int;

    -- FIX: edge detect combinatorially from registered prev value.
    -- spi_rise and spi_fall are single sys-clk wide pulses.
    -- We use these to gate all SPI shift logic instead of using
    -- spi_clk_int as an actual clock — keeps everything in one domain.
    spi_rise <= '1' when (spi_clk_int = '1' and spi_clk_prev = '0') else '0';
    spi_fall <= '1' when (spi_clk_int = '0' and spi_clk_prev = '1') else '0';

    -- =========================================================
    -- Bit counter
    -- FIX: moved into main clk process using spi_rise instead of
    -- clocking off spi_clk_int directly. Resets when leaving SAMPLE
    -- or DUMMY_CMD (handled in RESET_VALUES and IDLE transitions).
    -- =========================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                bit_cnt <= 0;
            else
                -- only count during active SPI states, on rising SPI edge
                if (state = SAMPLE or state = DUMMY_CMD) then
                    if spi_fall = '1' then
                        if bit_cnt = 15 then
                            bit_cnt <= 0;  -- auto-reset at end of transfer
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;
                    end if;
                else
                    bit_cnt <= 0;  -- hold at 0 whenever we're not shifting
                end if;
            end if;
        end if;
    end process;

    -- =========================================================
    -- Main sequential logic
    -- =========================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cmd_reg      <= X"8F1F";
				address 	 <= 512;  -- 0x0200
                shift_out    <= (others => '0');
                shift_in     <= (others => '0');
                sync_counter <= 0;


            else
                -- default outputs (overridden below as needed)
                SPI_CSn  <= '1';
				SPI_MOSI      <= '0';
                bus_rqst <= '0';
                bus_cmd  <= '0';

                case state is

                    when IDLE =>
                        if sync_counter < 10000 then
                            sync_counter <= sync_counter + 1;
                        end if;

                    when DUMMY_CMD =>
                        -- FIX: CSn stays low for all 16 bits, not just < 15
                        -- FIX: shifting happens on SPI clock edges, not every sys clk
                        SPI_CSn <= '0';
						dummy_sent <= 1;
                        SPI_MOSI <= '1';  -- all ones = X"FFFF" dummy command

                    when LOAD_CMD =>
                        shift_out <= cmd_reg;
                        -- FIX: reset sync_counter here so IDLE delay works
                        -- correctly on every subsequent loop iteration
                        sync_counter <= 0;

                    when SAMPLE =>
                        SPI_CSn <= '0';

                        -- Sample DOUT on FALLING edge (per ADC7928 timing)
                        if spi_fall = '1' then
                            shift_in  <= shift_in(14 downto 0) & SPI_MISO;
                            -- Also drive next MOSI bit on same falling edge
                            SPI_MOSI   <= shift_out(15);
                            shift_out <= shift_out(14 downto 0) & '0';
                        end if;

                    when ISSUE_BUS =>
                        bus_cmd  <= '1';
                        bus_data <= X"0" & shift_in(11 downto 0);
                        bus_addr <= std_logic_vector(to_unsigned(address, 16));

                        if bus_enable = '0' then
                            bus_rqst <= '1';
                        end if;

                    when RESET_VALUES =>
                        cmd_reg      <= X"8F1F";
						address 	 <= 512;  -- 0x0200
						shift_out    <= (others => '0');
						shift_in     <= (others => '0');
						sync_counter <= 0;

                end case;
            end if;
        end if;
    end process;

    -- =========================================================
    -- Next state logic
    -- =========================================================
    process(state, sync_counter, bit_cnt, bus_enable)
    begin
        next_state <= state;

        case state is

            when IDLE =>
                if sync_counter >= 10000 then
					if dummy_sent = 1 then
						next_state <= LOAD_CMD;
					else
						next_state <= DUMMY_CMD;
					end if;
                end if;

            when DUMMY_CMD =>
                -- FIX: wait until bit 15 has been fully clocked out
                -- (bit_cnt reaches 15 on the 16th rising edge)
                if bit_cnt = 15 then
                    next_state <= RESET_VALUES;
                end if;

            when LOAD_CMD =>
                next_state <= SAMPLE;

            when SAMPLE =>
                if bit_cnt = 15 then
                    next_state <= ISSUE_BUS;
                end if;

            when ISSUE_BUS =>
                if bus_enable = '1' then
                    next_state <= RESET_VALUES;
                end if;

            when RESET_VALUES =>
                next_state <= IDLE;

        end case;
    end process;

end architecture;
