-- =========================================================
-- =========================================================
-- ===================  Bus Master  ========================
-- =========================================================
-- =========================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_master is
    port (
        clk                 : in  std_logic;
        rst                 : in  std_logic;

        rs232_rqst            : in std_logic;
        rs232_en              : out std_logic;
		rs232_bus_data_store   : in std_logic_vector(15 downto 0);
		rs232_bus_data_send   : out std_logic_vector(15 downto 0);
        rs232_bus_cmd         : in std_logic;
        rs232_bus_addr        : in std_logic_vector(15 downto 0);
        rs232_bus_data_ready   : out std_logic;

        pwm_rqst            : in std_logic;
        pwm_en              : out std_logic;
		pwm_bus_data_send   : out std_logic_vector(15 downto 0);
        pwm_bus_cmd         : in std_logic;
        pwm_bus_addr        : in std_logic_vector(15 downto 0);
        pwm_bus_data_ready  : out std_logic;

        adc_rqst            : in std_logic;
        adc_en              : out std_logic;
		adc_bus_data_store  : in std_logic_vector(15 downto 0);
        adc_bus_cmd         : in std_logic;
        adc_bus_addr        : in std_logic_vector(15 downto 0);

        buck_rqst            : in std_logic;
        buck_en              : out std_logic;
		buck_bus_data_send   : out std_logic_vector(15 downto 0);
        buck_bus_cmd         : in std_logic;
        buck_bus_addr        : in std_logic_vector(15 downto 0);
        buck_bus_data_ready  : out std_logic;

        spram_addr          : out std_logic_vector(9 downto 0);
        spram_data_store    : out std_logic_vector(15 downto 0);
        spram_w_en          : out std_logic;
        spram_en            : out std_logic;
        spram_data_send     : in std_logic_vector(15 downto 0)
    );
end entity bus_master;


architecture behavioral of bus_master is
    type state is (
        IDLE,
		APPROVE,
		GET_DATA,
        WRITE_RAM,
        READ_RAM,
        SEND_DATA
    );
    signal current_state, next_state : state;

    signal data_reg     : std_logic_vector(15 downto 0);
    signal address_reg  : std_logic_vector(9 downto 0);

    signal curr_client  : integer range 0 to 15;
    signal misc_timer   : integer range 0 to 15;

begin
--===================================================
--================ CLOCKED PROCESSES ================
--===================================================

    -- STATE UPDATER PROCESS
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state <= IDLE;
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
                -- Default Assignments
                data_reg    <= (others => '0');
                address_reg <= (others => '0');
                misc_timer  <= 0;

            else
				spram_addr          <= (others => '0');
				spram_data_store    <= (others => '0');
				spram_w_en          <= '0';
				spram_en         	<= '0';

				rs232_en            <= '0';
				rs232_bus_data_send	<= (others => '0');
				rs232_bus_data_ready<= '0';

                pwm_en              <= '0';
				pwm_bus_data_send	<= (others => '0');
				pwm_bus_data_ready  <= '0';

				buck_en              <= '0';
				buck_bus_data_send	 <= (others => '0');
				buck_bus_data_ready  <= '0';

				adc_en               <= '0';


                case current_state is

                    when IDLE =>
                        misc_timer <= 5;

                        -- assign priority to pwm, but also enforce turn order
						if curr_client = 0 and pwm_rqst = '1' then
							curr_client <= curr_client + 1;

						elsif curr_client = 1 and adc_rqst = '1' then
							curr_client <= curr_client + 1;

						elsif curr_client = 2 and rs232_rqst = '1' then
							curr_client <= curr_client + 1;

						elsif curr_client = 3 and buck_rqst = '1' then
							curr_client <= curr_client + 1;

						elsif curr_client > 4 then
							 curr_client <= 0;
						else
							curr_client <= curr_client + 1;
						end if;

					when APPROVE =>
						if curr_client = 1 then
							pwm_en      <= '1';
						elsif curr_client = 2 then
							adc_en    <= '1';
						elsif curr_client = 3 then
							rs232_en    <= '1';
						elsif curr_client = 4 then
							buck_en		<= '1';
						end if;


                    when GET_DATA =>
						if curr_client = 1 then
							pwm_en      <= '1';
							address_reg <= pwm_bus_addr(9 downto 0);

						elsif curr_client = 2 then
							adc_en    <= '1';
							address_reg <= adc_bus_addr(9 downto 0);
							data_reg    <= adc_bus_data_store;

						elsif curr_client = 3 then
							rs232_en    <= '1';
							address_reg <= rs232_bus_addr(9 downto 0);
							data_reg    <= rs232_bus_data_store;

						elsif curr_client = 4 then
							buck_en    <= '1';
							address_reg <= buck_bus_addr(9 downto 0);

						end if;


                    when WRITE_RAM =>
						spram_addr          <= address_reg;
						spram_data_store    <= data_reg;
						spram_w_en          <= '1';
						spram_en            <= '1';

						if curr_client = 2 then
							adc_en    <= '1';
						elsif curr_client = 3 then
							rs232_en    <= '1';
						end if;

                        if misc_timer > 0 then
                            misc_timer <= misc_timer - 1;
                        end if;


					when READ_RAM =>
						spram_addr  <= address_reg;
						spram_en    <= '1';

						if curr_client = 1 then
                            pwm_en      <= '1';
                        elsif curr_client = 3 then
                            rs232_en    <= '1';
						elsif curr_client = 4 then
                            buck_en    <= '1';
                        end if;

						if misc_timer > 0 then
							misc_timer <= misc_timer - 1;
						else
							misc_timer <= 1;
						end if;


					when SEND_DATA =>
						spram_addr  <= address_reg;
						spram_en    <= '1';

						if curr_client = 1 then
							pwm_en      			<= '1';
							pwm_bus_data_send		<= spram_data_send;
							pwm_bus_data_ready 		<= '1';
						elsif curr_client = 3 then
							rs232_en    			<= '1';
							rs232_bus_data_send		<= spram_data_send;
							rs232_bus_data_ready 	<= '1';
						elsif curr_client = 4 then
							buck_en      			<= '1';
							buck_bus_data_send		<= spram_data_send;
							buck_bus_data_ready 		<= '1';
						end if;


						if misc_timer > 0 then
							misc_timer <= misc_timer - 1;
						end if;

                    when others =>
                        null;

                end case;
            end if;
        end if;
    end process;


--=======================================================
--================ COMBINATORIAL PROCESS ================
--=======================================================

    process(current_state, curr_client, pwm_rqst, adc_rqst, rs232_rqst, pwm_bus_cmd, adc_bus_cmd, rs232_bus_cmd, misc_timer)
    begin
        -- DEFAULTS (VERY IMPORTANT)
        next_state <= current_state;

        case current_state is

                when IDLE =>
					--only start if the client matches the request
                    if curr_client = 0 and pwm_rqst = '1' then
                        next_state	<= APPROVE;
					elsif curr_client = 1 and adc_rqst = '1' then
						next_state	<= APPROVE;
					elsif curr_client = 2 and rs232_rqst = '1' then
						next_state	<= APPROVE;
					elsif curr_client = 3 and buck_rqst = '1' then
						next_state	<= APPROVE;
                    end if;

				when APPROVE =>
					next_state <= GET_DATA;

                when GET_DATA =>
					if (curr_client = 2 and adc_bus_cmd = '1') or
					   (curr_client = 3 and rs232_bus_cmd = '1') then
						next_state <= WRITE_RAM;

					elsif (curr_client = 1 and pwm_bus_cmd = '0') or
						  (curr_client = 3 and rs232_bus_cmd = '0') or
						  (curr_client = 4 and buck_bus_cmd = '0') then
						  next_state <= READ_RAM;
					else
						next_state <= READ_RAM;
					end if;

                when WRITE_RAM =>
                    if misc_timer = 0 then
                        next_state <= IDLE;
                    end if;

                when READ_RAM =>
                    if misc_timer = 0 then
                        next_state <= SEND_DATA;
                    end if;

                when SEND_DATA =>
					if misc_timer = 0 then
						next_state <= IDLE;
					end if;
            end case;
    end process;
end architecture behavioral;
