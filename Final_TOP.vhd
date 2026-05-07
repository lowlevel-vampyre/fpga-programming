-- ===================================================================
-- ===================================================================
-- ===================  TOP: FINAL PROJECT  ========================
-- ===================================================================
-- ===================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity final is
    generic (
		--BAUD_DIV   : integer;
        BAUD_DIV   : integer := 2597;
        FIFO_DEPTH : integer := 16
    );
    port (
        rx : in  std_logic;
        tx : out std_logic;

		SPI_clk : out std_logic;
        SPI_MOSI : out std_logic;  -- MOSI
        SPI_MISO : in  std_logic;  -- MISO
        SPI_CSn : out std_logic;

        DSP_G1 : out std_logic;

		LED_1 : out std_logic;
		LED_2 : out std_logic;
		LED_3 : out std_logic;
		LED_4 : out std_logic;
		LED_5 : out std_logic;
		LED_6 : out std_logic;
		LED_7 : out std_logic;
		LED_8 : out std_logic
    );
end entity final;

architecture structural of final is

    -- ---------------------------------------------------------------
    -- Internal wiring
    -- ---------------------------------------------------------------
    signal clk : std_logic;
    signal rst : std_logic;

    -- RS232 to Bus Master
	signal rs232_rqst     		: std_logic;
    signal rs232_en       		: std_logic;
	signal rs232_bus_data_send	: std_logic_vector(15 downto 0);
	signal rs232_bus_data_store	: std_logic_vector(15 downto 0);
    signal rs232_bus_data_ready	: std_logic;
    signal rs232_bus_cmd      	: std_logic;
    signal rs232_bus_addr      	: std_logic_vector(15 downto 0);

	-- ADC to Bus Master
	signal adc_rqst     		: std_logic;
    signal adc_en       		: std_logic;
	signal adc_bus_data_store  	: std_logic_vector(15 downto 0);
    signal adc_bus_cmd        	: std_logic;
    signal adc_bus_addr       	: std_logic_vector(15 downto 0);

	-- PWM to Bus Master
    signal pwm_rqst       : std_logic;
    signal pwm_en         : std_logic;
	signal pwm_bus_data_send    : std_logic_vector(15 downto 0);
    signal pwm_bus_data_ready : std_logic;
    signal pwm_bus_cmd        : std_logic;
    signal pwm_bus_addr       : std_logic_vector(15 downto 0);

    -- BUCK to Bus Master
    signal buck_rqst       : std_logic;
    signal buck_en         : std_logic;
	signal buck_bus_data_send    : std_logic_vector(15 downto 0);
    signal buck_bus_data_ready : std_logic;
    signal buck_bus_cmd        : std_logic;
    signal buck_bus_addr       : std_logic_vector(15 downto 0);

    -- Bus Master to SPRAM
    signal spram_addr       : std_logic_vector(9 downto 0);
    signal spram_data_store : std_logic_vector(15 downto 0);
    signal spram_w_en       : std_logic;
    signal spram_en         : std_logic;
    signal spram_data_send  : std_logic_vector(15 downto 0);

begin
	LED_5 <= '1';
    LED_6 <= '1';
    LED_7 <= '1';
    LED_8 <= '1';

    U_CLK_GEN : entity work.clk_gen
        port map (
            clk_out => clk,
            rst_out => rst
        );

    U_RS232 : entity work.rs232
        generic map (
            BAUD_DIV   => BAUD_DIV,
            FIFO_DEPTH => FIFO_DEPTH
        )
        port map (
            clk            => clk,
            rst            => rst,
            rx             => rx,
            tx             => tx,
			bus_data_send  => rs232_bus_data_send,
            bus_data_store => rs232_bus_data_store,
            bus_enable     => rs232_en,
			bus_rqst	   => rs232_rqst,
            bus_data_ready => rs232_bus_data_ready,
            bus_cmd        => rs232_bus_cmd,
            bus_addr       => rs232_bus_addr
        );

	U_PWM : entity work.led_controller
        port map (
            clk            => clk,
            rst            => rst,
            bus_data 	   => pwm_bus_data_send,
            bus_enable     => pwm_en,
			bus_rqst	   => pwm_rqst,
            bus_data_ready => pwm_bus_data_ready,
            bus_cmd        => pwm_bus_cmd,
            bus_addr       => pwm_bus_addr,
			LED_1			=> LED_1,
			LED_2			=> LED_2,
			LED_3			=> LED_3,
			LED_4			=> LED_4
        );

    U_BUCK : entity work.buck_controller
        port map (
            clk            => clk,
            rst            => rst,
            DSP_G1         => DSP_G1,
            bus_data 	   => buck_bus_data_send,
            bus_enable     => buck_en,
			bus_rqst	   => buck_rqst,
            bus_data_ready => buck_bus_data_ready,
            bus_cmd        => buck_bus_cmd,
            bus_addr       => buck_bus_addr
        );

	U_SPI : entity work.adc_controller
        port map (
            clk            => clk,
            rst            => rst,
			SPI_clk        => SPI_clk,
			SPI_MOSI        => SPI_MOSI,
			SPI_MISO       => SPI_MISO,
			SPI_CSn        => SPI_CSn,
            bus_data 	   => adc_bus_data_store,
            bus_enable     => adc_en,
			bus_rqst	   => adc_rqst,
            bus_cmd        => adc_bus_cmd,
            bus_addr       => adc_bus_addr
        );

    U_BUS_MASTER : entity work.bus_master
        port map (
            clk             		=> clk,
            rst             		=> rst,

			rs232_rqst				=> rs232_rqst,
			rs232_en				=> rs232_en,
			rs232_bus_data_store	=> rs232_bus_data_store,
			rs232_bus_data_send		=> rs232_bus_data_send,
			rs232_bus_cmd 			=> rs232_bus_cmd,
			rs232_bus_addr   		=> rs232_bus_addr,
			rs232_bus_data_ready  	=> rs232_bus_data_ready,

			adc_bus_data_store 	   	=> adc_bus_data_store,
            adc_en     				=> adc_en,
			adc_rqst	  			=> adc_rqst,
            adc_bus_cmd        		=> adc_bus_cmd,
            adc_bus_addr       		=> adc_bus_addr,

			pwm_rqst          		=> pwm_rqst,
			pwm_en             		=> pwm_en,
			pwm_bus_data_send   	=> pwm_bus_data_send,
			pwm_bus_cmd          	=> pwm_bus_cmd,
			pwm_bus_addr       		=> pwm_bus_addr,
			pwm_bus_data_ready  	=> pwm_bus_data_ready,

            buck_rqst          		=> buck_rqst,
			buck_en             	=> buck_en,
			buck_bus_data_send   	=> buck_bus_data_send,
			buck_bus_cmd          	=> buck_bus_cmd,
			buck_bus_addr       	=> buck_bus_addr,
			buck_bus_data_ready  	=> buck_bus_data_ready,

            spram_addr      		=> spram_addr,
            spram_data_store		=> spram_data_store,
            spram_w_en      		=> spram_w_en,
            spram_en        		=> spram_en,
            spram_data_send 		=> spram_data_send
        );

    -- LATTICE FPGA MODULE -- Distributed SPRAM
    --
    -- Address Depth = 1024
    -- Data Width = 16
    -- Enable Output Register
    -- Memory File format: Addressed Hex
    -- Bus Ordering Style = MSB:LSB

    U_SPRAM : entity work.spram_TOP
        port map (
            Clock   => clk,
            Reset   => rst,
            Address => spram_addr,
            Data    => spram_data_store,
            WE      => spram_w_en,
            ClockEn => spram_en,
            Q       => spram_data_send
        );
end architecture structural;
