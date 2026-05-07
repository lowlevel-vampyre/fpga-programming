-- =================================================================
-- =================================================================
-- =======================  LED CONTROLLER  ========================
-- =================================================================
-- =================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

entity led_controller is
    port (
        --From Clock
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- from LED's
        LED_1           : out std_logic;
        LED_2           : out std_logic;
        LED_3           : out std_logic;
        LED_4           : out std_logic;

        -- From Bus Master
        bus_data        : in std_logic_vector(15 downto 0);
        bus_rqst        : out std_logic;
        bus_addr        : out std_logic_vector(15 downto 0);
        bus_cmd         : out std_logic;
        bus_data_ready  : in  std_logic;
        bus_enable      : in  std_logic

        --From LED's
    );
end entity led_controller;


architecture behavioral of led_controller is
    type state is (
        COUNT,
        REQUEST_DATA,
        REQUEST_DATA_IDLE
    );
    signal current_state, next_state : state;

    signal enable_mask  : std_logic_vector(15 downto 0);

	signal blink_freq     : integer range 0 to 65535;
	signal blink_ontime     : integer range 0 to 65535;
	signal led_1_duty    : integer range 0 to 65535;
	signal led_2_duty    : integer range 0 to 65535;
	signal led_3_duty    : integer range 0 to 65535;
	signal led_4_duty    : integer range 0 to 65535;
	signal pwm_counter   : integer range 0 to 65535;
	signal blink_counter : integer range 0 to 65535;
	signal refresh_counter : integer range 0 to 65535;
    signal address       : integer range 0 to 65535;
	signal word_index    : integer range 0 to 15;
    signal misc_val	     : integer range 0 to 32;


begin
--===================================================
--================ CLOCKED PROCESSES ================
--===================================================

    -- STATE UPDATER PROCESS
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state <= COUNT;
            else
                current_state <= next_state;
            end if;
        end if;
    end process;

    -- ASSIGN CLOCKED VALUES
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                enable_mask <= (others => '0');
                blink_freq   <= 65535;
				blink_ontime <= 65535;
                led_1_duty  <= 0;
                led_2_duty  <= 0;
                led_3_duty  <= 0;
                led_4_duty  <= 0;
				address 	<= 256; --256 = 0100
                word_index  <= 0;
                pwm_counter <= 0;
                misc_val    <= 0;

            else
				bus_addr    <= (others => '0');
                bus_rqst    <= '0';
                bus_cmd  <= '0';

                case current_state is

                    when COUNT =>

                        if pwm_counter >= 4084 then
                            pwm_counter <= 0;
                        else
                            pwm_counter <= pwm_counter + 1;
                        end if;

						if refresh_counter >= 60000 then
							refresh_counter <= 0;
						else
							refresh_counter <= refresh_counter + 1;
						end if;

                        if blink_counter = blink_freq then
							blink_counter <= 0;
                        elsif pwm_counter >= 4084 then
                            blink_counter <= blink_counter + 1;
                        end if;


					when REQUEST_DATA =>
						bus_addr <= std_logic_vector(to_unsigned((address + word_index), 16));

						if bus_enable = '0' then
							bus_rqst <= '1';
						else
							bus_rqst <= '0';
							misc_val <= word_index + 1;
						end if;


					when REQUEST_DATA_IDLE =>
						if bus_data_ready = '1' then
							case word_index is
								when 0 => enable_mask  <= bus_data;
								when 1 => blink_freq   <= to_integer(unsigned(bus_data));
								when 2 => blink_ontime <= to_integer(unsigned(bus_data));
								when 3 => led_1_duty <= to_integer(resize(unsigned(bus_data) * to_unsigned(4084, 16), 32)(31 downto 16));
								when 4 => led_2_duty <= to_integer(resize(unsigned(bus_data) * to_unsigned(4084, 16), 32)(31 downto 16));
								when 5 => led_3_duty <= to_integer(resize(unsigned(bus_data) * to_unsigned(4084, 16), 32)(31 downto 16));
								when 6 => led_4_duty <= to_integer(resize(unsigned(bus_data) * to_unsigned(4084, 16), 32)(31 downto 16));
								when others => null;
							end case;
						end if;

						if bus_enable = '0' then
							word_index <= misc_val;
						end if;
						if bus_enable = '0' and misc_val = 7 then
							word_index <= 0;
							misc_val   <= 0;
						end if;
                end case;
            end if;
        end if;
    end process;


--=======================================================
--================ COMBINATORIAL PROCESS ================
--=======================================================
	process(blink_counter, pwm_counter, enable_mask, led_1_duty, led_2_duty, led_3_duty, led_4_duty, blink_ontime)
	begin
		LED_1 <= '1'; LED_2 <= '1'; LED_3 <= '1'; LED_4 <= '1';
		if blink_counter < blink_ontime then
			if pwm_counter < led_1_duty then LED_1 <= not enable_mask(0);  end if;
			if pwm_counter < led_2_duty then LED_2 <= not enable_mask(4);  end if;
			if pwm_counter < led_3_duty then LED_3 <= not enable_mask(8); end if;
			if pwm_counter < led_4_duty then LED_4 <= not enable_mask(12); end if;
		end if;
	end process;


    process(current_state, bus_enable, refresh_counter, misc_val)
    begin
        -- DEFAULTS (VERY IMPORTANT)
        next_state <= current_state;

        case current_state is
                when COUNT =>
                    if refresh_counter >= 60000 then
                        next_state <= REQUEST_DATA;
                    end if;

                when REQUEST_DATA =>
					if bus_enable = '1' then
						next_state <= REQUEST_DATA_IDLE;
					end if;

				when REQUEST_DATA_IDLE =>
					if bus_enable = '0' then
						if misc_val = 7 then
							next_state <= COUNT;
						else
							next_state <= REQUEST_DATA;
						end if;
					end if;
		end case;
    end process;
end architecture behavioral;
