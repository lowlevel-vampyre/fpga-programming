-- =================================================================
-- =================================================================
-- =======================  BUCK CONTROLLER  ========================
-- =================================================================
-- =================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

entity buck_controller is
    port (
        --From Clock
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- to Buck Driver
        DSP_G1          : out std_logic;

        -- From Bus Master
        bus_data        : in std_logic_vector(15 downto 0);
        bus_rqst        : out std_logic;
        bus_addr        : out std_logic_vector(15 downto 0);
        bus_cmd         : out std_logic;
        bus_data_ready  : in  std_logic;
        bus_enable      : in  std_logic

    );
end entity buck_controller;


architecture behavioral of buck_controller is
    type state is (
        COUNT,
        REQUEST_DATA,
        REQUEST_DATA_IDLE
    );
    signal current_state, next_state : state;

	signal buck_duty    : integer range 0 to 65535;
	signal pwm_counter   : integer range 0 to 65535;
	signal refresh_counter : integer range 0 to 65535;
    signal address       : integer range 0 to 65535;

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
                buck_duty  <= 0;
                pwm_counter <= 0;
				address 	 <= 512;  -- 0x0200

            else
				bus_addr    <= (others => '0');
                bus_rqst    <= '0';
                bus_cmd  <= '0';

                case current_state is

                    when COUNT =>

                        -- roughly 10Khz
                        if pwm_counter >= 2500 then
                            pwm_counter <= 0;
                        else
                            pwm_counter <= pwm_counter + 1;
                        end if;

						if refresh_counter >= 60000 then
							refresh_counter <= 0;
						else
							refresh_counter <= refresh_counter + 1;
						end if;


					when REQUEST_DATA =>
						bus_addr <= std_logic_vector(to_unsigned((address), 16));

						if bus_enable = '0' then
							bus_rqst <= '1';
						else
							bus_rqst <= '0';
						end if;


					when REQUEST_DATA_IDLE =>
						if bus_data_ready = '1' then
                            buck_duty <= to_integer(resize(unsigned(bus_data) * to_unsigned(2500, 16), 32)(25 downto 16));
						end if;

                end case;
            end if;
        end if;
    end process;


--=======================================================
--================ COMBINATORIAL PROCESS ================
--=======================================================
	process(pwm_counter, buck_duty)
	begin
		DSP_G1 <= '0';
        if pwm_counter < buck_duty then DSP_G1 <= '1';  end if;
	end process;


    process(current_state, bus_enable, refresh_counter)
    begin
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
                        next_state <= COUNT;
					end if;
		end case;
    end process;
end architecture behavioral;
