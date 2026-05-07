-- ===================================================================
-- ===================================================================
-- ===================  TESTBENCH: FINAL  ==========================
-- ===================================================================
-- ===================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity final_tb is
end entity final_tb;

architecture behavioral of final_tb is

    -- Use a short baud div for simulation speed
    constant BAUD_DIV   : integer := 2597;
    constant CLK_PERIOD : time    := 40.11 ns;
    constant BIT_PERIOD : time    := BAUD_DIV * CLK_PERIOD;

    signal rx : std_logic := '1';
    signal tx : std_logic;

	signal SPI_clk : std_logic;
    signal SPI_MOSI : std_logic;
    signal SPI_MISO : std_logic := '0';
    signal SPI_CSn : std_logic;

	signal LED_1 : std_logic;
	signal LED_2 : std_logic;
	signal LED_3 : std_logic;
	signal LED_4 : std_logic;

    -- =========================================================
    -- Fake ADC signals
    -- FAKE_RESULT simulates channel 0 returning 0x0ABC (~67% full scale)
    -- Format: 0 | ADD[2:0]=000 | D[11:0]=0xABC
    -- =========================================================
    constant FAKE_RESULT  : std_logic_vector(15 downto 0) := X"0ABC";
    signal adc_shift_reg  : std_logic_vector(15 downto 0) := FAKE_RESULT;

begin

    U_DUT : entity work.final
        generic map (
            BAUD_DIV   => BAUD_DIV,
            FIFO_DEPTH => 16
        )
        port map (
            rx => rx,
            tx => tx,
			SPI_clk => SPI_clk,
			SPI_MOSI => SPI_MOSI,
			SPI_MISO => SPI_MISO,
			SPI_CSn => SPI_CSn,
			LED_1 => LED_1,
			LED_2 => LED_2,
			LED_3 => LED_3,
			LED_4 => LED_4
        );

    -- =========================================================
    -- Fake ADC process
    -- Runs concurrently with the stim process the whole simulation.
    -- On each falling SPI clock edge, shifts the next bit of
    -- FAKE_RESULT onto SPI_MISO, just like the real AD7928 would.
    -- Reloads the fake result word each time CSn goes low so every
    -- transaction gets a fresh copy to shift out.
    -- =========================================================
    fake_adc : process(SPI_clk, SPI_CSn)
    begin
        if falling_edge(SPI_CSn) then
            adc_shift_reg <= FAKE_RESULT;

        elsif falling_edge(SPI_clk) then
            if SPI_CSn = '0' then
                SPI_MISO     <= adc_shift_reg(15);
                adc_shift_reg <= adc_shift_reg(14 downto 0) & '0';
            else
                SPI_MISO <= '0';
            end if;
        end if;
    end process;

    -- =========================================================
    -- Stimulus process
    -- =========================================================
    stim : process

        procedure send_byte(data : std_logic_vector(7 downto 0)) is
        begin
            rx <= '0';
            wait for BIT_PERIOD;
            for i in 0 to 7 loop
                rx <= data(i);
                wait for BIT_PERIOD;
            end loop;
            rx <= '1';
            wait for BIT_PERIOD;
        end procedure;

        procedure gap is
        begin
            wait for 100000 ns;
        end procedure;

    begin
        -- clk_gen handles reset internally, just wait for it to settle
        wait for 3 ms;

 		report "=== TEST 5: Write LED registers to addr 0x0100 ===" severity note;
		send_byte(x"7E");  -- start delimiter
		send_byte(x"12");  -- length = 18
		send_byte(x"0A");  -- op: write
		send_byte(x"07");  -- reg count = 7

		send_byte(x"01");  -- addr high
		send_byte(x"00");  -- addr low

		send_byte(x"00");  -- LED enable high
		send_byte(x"01");  -- LED enable low

		send_byte(x"FF");  -- blink period high
		send_byte(x"FF");  -- blink period low

		send_byte(x"8F");  -- LED on time high
		send_byte(x"FF");  -- LED on time low

		send_byte(x"20");  -- LED 1 intensity high
		send_byte(x"00");  -- LED 1 intensity low

		send_byte(x"40");  -- LED 2 intensity high
		send_byte(x"00");  -- LED 2 intensity low

		send_byte(x"80");  -- LED 3 intensity high
		send_byte(x"00");  -- LED 3 intensity low

		send_byte(x"FF");  -- LED 4 intensity high
		send_byte(x"FF");  -- LED 4 intensity low

		send_byte(x"82");  -- checksum
		wait for 5 ms;


		report "=== TEST 3: Read 1 register from addr 0x0001 ===" severity note;

        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"07");  -- reg count = 1

        send_byte(x"01");  -- addr high
        send_byte(x"00");  -- addr low

        send_byte(x"E8");   -- checksum

        wait for 5 ms;

        -- -------------------------------------------------------
        -- TEST 1: Write 1 register
        -- Write 0x00AB to address 0x0000
        -- Expect: ACK (0x06) on tx
        -- -------------------------------------------------------
        report "=== TEST 1: Write 0x00AB to addr 0x0001 ===" severity note;

        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1

        send_byte(x"00");  -- addr high
        send_byte(x"01");  -- addr low

        send_byte(x"00");  -- data high
        send_byte(x"AB");  -- data low

        send_byte(x"48");       -- checksum

        wait for 2 ms;

		-- -------------------------------------------------------
        -- TEST 3: Write 3 registers then read them back
        -- Write 0x1111, 0x2222, 0x3333 to addr 0x0005
        -- Then read 3 registers from addr 0x0005
        -- Expect: ACK, then 0x1111 0x2222 0x3333 on tx
        -- -------------------------------------------------------
        report "=== TEST 2: Write 3 registers to addr 0x0005 ===" severity note;

        send_byte(x"7E");  -- start
        send_byte(x"0A");  -- length = 10
        send_byte(x"0A");  -- op: write
        send_byte(x"03");  -- reg count = 3

        send_byte(x"00");  -- addr high
        send_byte(x"05");  -- addr low

        send_byte(x"11");  -- reg 0 high
        send_byte(x"11");  -- reg 0 low

        send_byte(x"22");  -- reg 1 high
        send_byte(x"22");  -- reg 1 low

        send_byte(x"33");  -- reg 2 high
        send_byte(x"33");  -- reg 2 low

        send_byte(x"1B");       -- checksum

        wait for 2 ms;

		-- -------------------------------------------------------
        -- TEST 2: Read back that same register
        -- Read 1 register from address 0x0000
        -- Expect: 0x00AB back on tx
        -- -------------------------------------------------------
        report "=== TEST 3: Read 1 register from addr 0x0001 ===" severity note;

        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"01");  -- reg count = 1

        send_byte(x"00");  -- addr high
        send_byte(x"01");  -- addr low

        send_byte(x"EE");   -- checksum

        wait for 5 ms;


        report "=== TEST 4: Read 3 registers from addr 0x0005 ===" severity note;

        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"03");  -- reg count = 3
        send_byte(x"00");  -- addr high
        send_byte(x"05");  -- addr low
        send_byte(x"E8");       -- checksum

        wait for 7 ms;


		-- -------------------------------------------------------
        -- TEST 4: Write to last valid address
        -- Write 0xFFFF to addr 0x03FF (max 10-bit SPRAM address)
        -- Expect: ACK
        -- -------------------------------------------------------
        report "=== TEST 5: Write 0xFFFF to max addr 0x03FF ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1
        send_byte(x"03");  -- addr high
        send_byte(x"FF");  -- addr low
        send_byte(x"FF");  -- data high
        send_byte(x"FF");  -- data low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        -- read it back
        report "=== TEST 6: Read back 0xFFFF from addr 0x03FF ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"01");  -- reg count = 1
        send_byte(x"03");  -- addr high
        send_byte(x"FF");  -- addr low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        -- -------------------------------------------------------
        -- TEST 5: Write 0x0000 (all zeros) to addr 0x0002
        -- Tests that zero data doesn't get swallowed or misread
        -- Expect: ACK
        -- -------------------------------------------------------
        report "=== TEST 7: Write 0x0000 to addr 0x0002 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"02");  -- addr low
        send_byte(x"00");  -- data high
        send_byte(x"00");  -- data low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        report "=== TEST 8: Read back 0x0000 from addr 0x0002 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"02");  -- addr low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        -- -------------------------------------------------------
        -- TEST 6: Back to back writes to adjacent addresses
        -- Write 0xAAAA to 0x0010, then immediately 0x5555 to 0x0011
        -- Tests that decoder resets cleanly between packets
        -- Expect: ACK, ACK
        -- -------------------------------------------------------
        report "=== TEST 9: Write 0xAAAA to addr 0x0010 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"10");  -- addr low
        send_byte(x"AA");  -- data high
        send_byte(x"AA");  -- data low
        send_byte(x"FF");  -- checksum
        wait for 1 ms;

        report "=== TEST 10: Write 0x5555 to addr 0x0011 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"11");  -- addr low
        send_byte(x"55");  -- data high
        send_byte(x"55");  -- data low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        report "=== TEST 11: Read back both registers ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"02");  -- reg count = 2
        send_byte(x"00");  -- addr high
        send_byte(x"10");  -- addr low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        -- -------------------------------------------------------
        -- TEST 7: Overwrite an existing register
        -- First write 0x1234 to addr 0x0001, then overwrite with 0x5678
        -- Read back should return 0x5678 not 0x1234
        -- -------------------------------------------------------
        report "=== TEST 12: Write 0x1234 to addr 0x0001 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"01");  -- addr low
        send_byte(x"12");  -- data high
        send_byte(x"34");  -- data low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        report "=== TEST 13: Overwrite addr 0x0001 with 0x5678 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"06");  -- length
        send_byte(x"0A");  -- op: write
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"01");  -- addr low
        send_byte(x"56");  -- data high
        send_byte(x"78");  -- data low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        report "=== TEST 14: Read back addr 0x0001, expect 0x5678 ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"01");  -- reg count = 1
        send_byte(x"00");  -- addr high
        send_byte(x"01");  -- addr low
        send_byte(x"FF");  -- checksum
        wait for 2 ms;

        -- -------------------------------------------------------
        -- TEST ADC: Read back ADC register at 0x0200
        -- By this point the spi_adc module should have already
        -- written 0x0ABC to SPRAM[0x0200] multiple times.
        -- Expect: 0x0ABC on tx
        -- -------------------------------------------------------
        report "=== TEST ADC: Read ADC value from addr 0x0200, expect 0x0ABC ===" severity note;
        send_byte(x"7E");  -- start
        send_byte(x"04");  -- length
        send_byte(x"0F");  -- op: read
        send_byte(x"01");  -- reg count = 1
        send_byte(x"02");  -- addr high
        send_byte(x"00");  -- addr low
        send_byte(x"FF");  -- checksum
        wait for 5 ms;

        report "=== All tests complete ===" severity note;
        wait;
    end process;

end architecture behavioral;
