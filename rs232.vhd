-- updated 04/15/2026, 16:25

-- ==================================================================
-- ==================================================================
-- ===================  MODULE 1: BAUD GENERATOR  ===================
-- ==================================================================
-- ==================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity baud_generator is
    generic (
        BAUD_DIV : integer
    );
    port (
        -- INTERNAL SIGNALS
        clk     : in  std_logic;
        rst     : in  std_logic;

        -- FROM RX
        enable : in std_logic;
        tick : out std_logic
    );
end entity baud_generator;

architecture behavioral of baud_generator is
    type state_type is (IDLE, START, PULSE, COUNT);
    signal current_state, next_state : state_type;

    signal baud_cnt   : integer range 0 to BAUD_DIV + BAUD_DIV/8;
    signal start_done : std_logic;

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

    -- DATAPATH
    -- On START entry: load counter to BAUD_DIV + BAUD_DIV/8 so the first
    -- sample lands near the middle of bit 0 (accounting for the start bit).
    -- Thereafter COUNT down from BAUD_DIV for each subsequent bit.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                baud_cnt   <= 0;
                start_done <= '0';
            else
				tick <= '0';

                case current_state is

                    when IDLE =>
                        start_done <= '0';

                    when START =>
                        if start_done = '0' then
                            baud_cnt   <= BAUD_DIV + BAUD_DIV/8;
                            start_done <= '1';
                        end if;

                    when COUNT =>
					tick <= '0';
                        if baud_cnt > 0 then
                            baud_cnt <= baud_cnt - 1;
                        end if;

                    when PULSE =>
						tick <= '1';
                        baud_cnt <= BAUD_DIV;

                end case;
            end if;
        end if;
    end process;


--=======================================================
--================ COMBINATORIAL PROCESS ================
--=======================================================

    process(current_state, enable, baud_cnt, start_done)
    begin

        next_state <= current_state;

        case current_state is

            when IDLE =>
                if enable = '1' then
                    next_state <= START;
                end if;

            when START =>
                -- Wait until the counter has been loaded, then start counting
                if start_done = '1' then
                    next_state <= COUNT;
                end if;

            when PULSE =>
                next_state <= COUNT;

            when COUNT =>
                if enable = '0' then
                    next_state <= IDLE;
                end if;

                if baud_cnt = 0 then
                    next_state <= PULSE;
                end if;

        end case;
    end process;

end architecture behavioral;
















-- ===========================================================
-- ===========================================================
-- ===================  MODULE 2: UART RX  ===================
-- ===========================================================
-- ===========================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    port (
        -- INTERNAL SIGNALS
        clk        : in  std_logic;
        rst        : in  std_logic;

        -- BAUD GENERATOR
        baud_en    : out std_logic;
        baud_tick  : in  std_logic;

        -- TO FIFO
        byte_save  : out std_logic_vector(7 downto 0);
        byte_ready : out std_logic;

        -- EXTERNAL SIGNAL
        rx         : in std_logic
    );
end entity uart_rx;

architecture behavioral of uart_rx is
    type state is (IDLE, START_RCV, SAMPLE, PAUSE, STORE, STOP);
    signal current_state, next_state : state;

    signal shift_reg : std_logic_vector(7 downto 0);
    signal bit_index : integer range 0 to 7;


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

    -- NOTE:
    -- The Baud generator already adds a small amount of time to the tick.
    --      the tick is delayed, so as to sample in the middle of the signal
    -- ASSIGN CLOCKED VALUES
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                shift_reg <= (others => '0');
                bit_index <= 0;
            else
				-- DEFAULTS
				baud_en    <= '0';
				byte_ready <= '0';
				byte_save  <= (others => '0');

				case current_state is

					when START_RCV =>
						baud_en <= '1';
						shift_reg <= (others => '0');
						bit_index <= 0;

					when PAUSE =>
						baud_en <= '1';

					when SAMPLE =>
						baud_en <= '1';

						shift_reg <= rx & shift_reg(7 downto 1);   -- LSB first

						if bit_index < 7 then
							bit_index <= bit_index + 1;
						end if;

					when STORE =>
						baud_en    <= '1';
						byte_save  <= shift_reg;
						byte_ready <= '1';

					when STOP =>
						baud_en <= '1';

					when others =>
                        null;
				end case;
			end if;
		end if;
    end process;


--=======================================================
--================ COMBINATORIAL PROCESS ================
--=======================================================

    process(current_state, rx, baud_tick, bit_index, shift_reg)
    begin

        next_state <= current_state;

        case current_state is

            when IDLE =>
                if rx = '0' then
                    next_state <= START_RCV;
                end if;

            when START_RCV =>
                next_state <= PAUSE;

            when PAUSE =>
                -- Wait for the next baud tick, then go sample
                if baud_tick = '1' then
                    next_state <= SAMPLE;
                end if;

            when SAMPLE =>
                -- rx is being registered this clock cycle (in the clocked process).
                -- After the 8th sample (bit_index already at 7 going in), go to STORE.
                -- Otherwise go back to PAUSE to wait for the next tick.
                if bit_index = 7 then
                    next_state <= STORE;
                else
                    next_state <= PAUSE;
                end if;

            when STORE =>
				next_state <= STOP;

			when STOP =>
				if rx = '1' then
					next_state <= IDLE;
				end if;

        end case;    end process;
end architecture behavioral;















-- ===========================================================
-- ===========================================================
-- ===================  MODULE 3: UART TX  ===================
-- ===========================================================
-- ===========================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    port (
        -- INTERNAL SIGNALS
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- BAUD GENERATOR
        baud_en   : out std_logic;
        baud_tick : in  std_logic;

        -- FROM DECODER
        data_in   : in  std_logic_vector(7 downto 0);
        start     : in  std_logic;
        busy      : out std_logic;

        -- EXTERNAL SIGNAL
        tx        : out std_logic
    );
end entity uart_tx;

architecture behavioral of uart_tx is
    type state is (IDLE, SKIP, START_SEND, SENDING, STOP);
    signal current_state, next_state : state;

    signal shift_reg  : std_logic_vector(7 downto 0);
    signal bit_index  : integer range 0 to 7;


begin
--===================================================
--================ CLOCKED PROCESSES ================
--===================================================

-- decoder starts by pulsing start high, and the data is now available
-- tx then holds busy high, and starts the clock.
-- tx waits for the first baud tick before it starts sending to avoid first tick timing
--

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
                shift_reg <= (others => '0');
                bit_index <= 0;

            else
			    baud_en    <= '0';
				busy       <= '1';
				tx         <= '1';  -- idle high

                case current_state is

                    when IDLE =>
						busy <= '0';

                        -- Latch data as soon as start is asserted
                        if start = '1' then
							baud_en 	<= '1';
                            shift_reg 	<= data_in;
                            bit_index 	<= 0;
							busy       	<= '1';
                        end if;

					when SKIP =>
						baud_en <= '1';

					when START_SEND =>
						baud_en <= '1';
						tx      <= '0';  -- start bit (low)

                    when SENDING =>
						baud_en <= '1';
						tx      <= shift_reg(0);  -- LSB first

                        -- Shift out LSB first on each baud tick
                        if baud_tick = '1' then
                            shift_reg <= '0' & shift_reg(7 downto 1);
                            if bit_index < 7 then
                                bit_index <= bit_index + 1;
                            end if;
                        end if;

                    when STOP =>
						baud_en <= '1';
						tx      <= '1';  -- stop bit (high)

						if baud_tick = '1' then
							busy <= '0';
						end if;

                        -- Latch data as soon as start is asserted
                        if start = '1' then
                            shift_reg <= data_in;
                            bit_index <= 0;
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

    process(current_state, start, baud_tick, bit_index, shift_reg)
    begin

		next_state <= current_state;

        case current_state is

            when IDLE =>
                if start = '1' then
                    next_state <= SKIP;
                end if;

            when SKIP =>
                --catch extra long tick before starting
                if baud_tick = '1' then
                    next_state <= START_SEND;
                end if;

            when START_SEND =>
                --wait here one full baud tick
                if baud_tick = '1' then
                    next_state <= SENDING;
                end if;

            when SENDING =>
                -- wait one full tick here for each bit
                if baud_tick = '1' then
                    if bit_index = 7 then
                        next_state <= STOP;
                    end if;
                end if;

            when STOP =>
                if baud_tick = '1' then
                    if start = '1' then
                        next_state <= START_SEND;
                    else
                        next_state <= IDLE;
                    end if;
                end if;

        end case;
    end process;
end architecture behavioral;



















-- ==============================================================
-- ==============================================================
-- ===================  MODULE 4: FIFO BUFFER  ==================
-- ==============================================================
-- ==============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is
    generic (
        DEPTH : integer := 16
    );
    port (
        -- INTERNAL SIGNALS
        clk        : in  std_logic;
        rst        : in  std_logic;
        -- FROM DECODER
        read_en    : in  std_logic;
        read_data  : out std_logic_vector(7 downto 0);
        empty      : out std_logic;
        -- FROM UART RX
        write_en   : in  std_logic;
        write_data : in  std_logic_vector(7 downto 0)
    );
end entity;

architecture behavioral of fifo is

    -- FSM States
    type state_type is (
        IDLE,       -- Waiting; data at tail is held stable on read_data
        READING,    -- read_en was seen; commit tail advance on this cycle
        WRITING     -- Isolated write cycle (no simultaneous read)
    );
    signal state : state_type := IDLE;

    type mem_type is array (0 to DEPTH-1) of std_logic_vector(7 downto 0);
    signal mem   : mem_type;

    signal head  : integer range 0 to DEPTH-1 := 0;
    signal tail  : integer range 0 to DEPTH-1 := 0;
    signal count : integer range 0 to DEPTH   := 0;

begin

--===================================================
--================ CLOCKED FSM =====================
--===================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                head      <= 0;
                tail      <= 0;
                count     <= 0;

            else
                case state is

                    -- -----------------------------------------------
                    -- IDLE: Hold current read_data stable.
                    --       Accept writes freely.
                    --       When read_en seen AND buffer not empty,
                    --       move to READING next cycle.
                    -- -----------------------------------------------
                    when IDLE =>
                        -- Service a write if one arrives
                        if write_en = '1' and count < DEPTH then
                            mem(head) <= write_data;
                            head      <= (head + 1) mod DEPTH;
                            count     <= count + 1;
                            state     <= WRITING;
                        end if;

                        -- read_en seen: move to READING to commit the pop
                        if read_en = '1' and count > 0 then
							tail  <= (tail + 1) mod DEPTH;
							count <= count - 1;
                            state <= READING;
                        end if;

                    -- -----------------------------------------------
                    -- READING: Commit the tail advance.
                    --          read_data was already placed in IDLE.
                    --          Decrement count, advance tail, go back
                    --          to IDLE (where next byte will be loaded).
                    -- -----------------------------------------------
                    when READING =>
                        state <= IDLE;

                    -- -----------------------------------------------
                    -- WRITING: Single-cycle write commit, return IDLE.
                    --          (Prevents simultaneous read/write
                    --           pointer collision on the same cycle.)
                    -- -----------------------------------------------
                    when WRITING =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

--===================================================
--================ COMBINATIONAL OUTPUTS ============
--===================================================
	read_data <= mem(tail) when count > 0 else (others => '0');
    empty <= '1' when count = 0 else '0';

end architecture;























-- ================================================================
-- ================================================================
-- ===================  MODULE 5: Decoder  ========================
-- ================================================================
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decoder is
    port (
        --From Clock
        clk             : in  std_logic;
        rst             : in  std_logic;

        --From FIFO
        fifo_read_data	: in std_logic_vector(7 downto 0);
        fifo_empty      : in std_logic;
        fifo_read_en    : out std_logic;

        --From Bus Master
        bus_data_store  : out std_logic_vector(15 downto 0);
		bus_data_send	: in std_logic_vector(15 downto 0);
        bus_enable      : in std_logic;
        bus_data_ready  : in std_logic;
        bus_cmd         : out std_logic;
        bus_addr        : out std_logic_vector(15 downto 0);
        bus_rqst        : out std_logic;

        --From uart_tx
        tx_data         : out std_logic_vector(7 downto 0);
        tx_start        : out std_logic;
        tx_busy         : in std_logic
    );
end entity decoder;


architecture behavioral of decoder is
    type state is (
        IDLE,
        GET_START,
        GET_LEN,
        GET_OP,
        GET_REG_CNT,
        GET_ADDR,
        GET_DATA,
        GET_CHCK_SUM,
        VERIFY_CHCK_SUM,
        ISSUE_BUS,
		ISSUE_IDLE,
        READ_BUS,
		READ_IDLE,
		BUILD_PKT,
        SEND_DATA,
		SEND_IDLE,
        RESET_VALUES
    );
    signal current_state, next_state : state;

    type data_array 	is array (0 to 15) of std_logic_vector(15 downto 0);
    type addr_array  	is array (0 to 15) of std_logic_vector(15 downto 0);
	type tx_array 		is array (0 to 37) of std_logic_vector(7 downto 0);


	signal addr_reg         : addr_array;
    signal data_reg         : data_array;
	signal tx_buf			: tx_array;

    signal start_byte       : std_logic_vector(7 downto 0);
    signal pkt_len          : std_logic_vector(7 downto 0);
    signal op_id            : std_logic_vector(7 downto 0);
    signal checksum         : std_logic_vector(7 downto 0);
    signal start_addr_tmp   : std_logic_vector(15 downto 0);

	signal prev_state 		: integer range 0 to 7;
	signal calc_chksum 		: integer range 0 to 65535;
	signal temp_calc_chksum : integer range 0 to 65535;
    signal start_addr       : integer range 0 to 65535;
    signal misc_timer       : integer range 0 to 15;
    signal temp_iterator    : integer range 0 to 63;
	signal misc_val			: integer range 0 to 31;
    signal packet_byte_cnt  : integer range -255 to 255;
    signal data_byte_cnt    : integer range -1 to 2;
    signal reg_cnt          : integer range 0 to 255;
	signal tx_byte_index 	: integer range 0 to 63;
	signal tx_len  			 : integer range 0 to 63;


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
                -- DEFAULT LOW
                start_byte 		<= (others => '0');
                pkt_len    		<= (others => '0');
                op_id      		<= (others => '0');
                checksum   		<= (others => '0');
				start_addr_tmp	<= (others => '0');
				calc_chksum	    <= 0;
				prev_state  	<= 0;
				reg_cnt    		<= 0;
                packet_byte_cnt <= 0;
                misc_timer 		<= 0;
				misc_val 		<= 0;
				tx_byte_index <= 0;

            else
				-- DEFAULTS (VERY IMPORTANT)
				fifo_read_en    <= '0';
				bus_rqst        <= '0';
				tx_start        <= '0';
				bus_cmd         <= '0';
				bus_data_store  <= (others => '0');
				bus_addr        <= (others => '0');
				tx_data         <= (others => '0');

                case current_state is

                    when IDLE =>
                        misc_timer <= 0;

						if fifo_empty = '0' then
							fifo_read_en <= '1';
						end if;


                    when GET_START =>
                        prev_state 		<= 1;
                        start_byte 		<= fifo_read_data;
                        misc_timer 		<= 3;


					when GET_LEN =>
                        prev_state 		 <= 2;
                        pkt_len     	 <= fifo_read_data;
                        packet_byte_cnt  <= to_integer(unsigned(fifo_read_data));


					when GET_OP =>
                        prev_state 		 <= 3;
                        op_id            <= fifo_read_data;

                        calc_chksum      <= calc_chksum + to_integer(unsigned(fifo_read_data));
                        packet_byte_cnt  <= packet_byte_cnt - 1;


					when GET_REG_CNT =>
                        prev_state 		 <= 4;
                        reg_cnt          <= to_integer(unsigned(fifo_read_data));
                        packet_byte_cnt  <= packet_byte_cnt - 1;

                        calc_chksum <= calc_chksum + to_integer(unsigned(fifo_read_data));
                        data_byte_cnt    <= 2;


					when GET_ADDR =>
						if data_byte_cnt = 2 then
							start_addr_tmp(15 downto 8) <= fifo_read_data;
							packet_byte_cnt  <= packet_byte_cnt - 1;
							data_byte_cnt    <= data_byte_cnt - 1;
							calc_chksum <= calc_chksum + to_integer(unsigned(fifo_read_data));

						elsif data_byte_cnt = 1 then
							start_addr_tmp(7 downto 0) <= fifo_read_data;
							packet_byte_cnt  <= packet_byte_cnt - 1;
							data_byte_cnt    <= data_byte_cnt - 1;
							calc_chksum <= calc_chksum + to_integer(unsigned(fifo_read_data));

						elsif data_byte_cnt = 0 then
                            data_byte_cnt	<= 2;
                            temp_iterator	<= 0;
                            start_addr		<= to_integer(unsigned(start_addr_tmp));

							if op_id = x"0A" then
								prev_state <= 5;
							elsif op_id = x"0F" then
								prev_state <= 6;
							end if;
						end if;

					when GET_DATA =>
                        if temp_iterator < reg_cnt then
                            if data_byte_cnt = 2 then
                                data_reg(temp_iterator)(15 downto 8) <= fifo_read_data;
                                packet_byte_cnt  <= packet_byte_cnt - 1;
                                data_byte_cnt    <= data_byte_cnt - 1;
                                calc_chksum <= calc_chksum + to_integer(unsigned(fifo_read_data));

                            elsif data_byte_cnt = 1 then
                                data_reg(temp_iterator)(7 downto 0) <= fifo_read_data;
                                packet_byte_cnt  <= packet_byte_cnt - 1;
                                data_byte_cnt    <= data_byte_cnt - 1;
                                calc_chksum <= calc_chksum + to_integer(unsigned(fifo_read_data));

                                -- since we have completed one data save, we can now calculate the address and cast back to std_logic_vector
                                addr_reg(temp_iterator) <= std_logic_vector(to_unsigned((start_addr + temp_iterator), 16));

                            elsif data_byte_cnt = 0 then
                                data_byte_cnt    <= 2;
                                temp_iterator <= temp_iterator + 1;
                            end if;
						end if;

						if temp_iterator = (reg_cnt - 1) and data_byte_cnt = 0 then
							prev_state <= 6;
                        end if;


                    when GET_CHCK_SUM =>
                        checksum <= fifo_read_data;
                        calc_chksum <= 255 - (calc_chksum mod 256);
                        temp_iterator	<= 0;

                    when VERIFY_CHCK_SUM =>
                        if to_integer(unsigned(checksum)) = calc_chksum then
                            calc_chksum	     <= 0;
                            temp_calc_chksum <= 0;
                        end if;

					when ISSUE_BUS =>
						bus_cmd        <= '1';
						bus_data_store <= data_reg(temp_iterator);
						bus_addr       <= addr_reg(temp_iterator);

						if bus_enable = '0' then
							bus_rqst <= '1';
						else
							bus_rqst <= '0';
							temp_iterator <= temp_iterator + 1;
						end if;


                    when ISSUE_IDLE =>
						if temp_iterator = reg_cnt then
							temp_iterator 	<= 0;
							misc_val		<= 0;
						end if;


					when READ_BUS =>
						bus_cmd        <= '0';
						bus_addr       <= std_logic_vector(to_unsigned((start_addr + temp_iterator), 16));
						calc_chksum    <= temp_calc_chksum;

						if bus_enable = '0' then
							bus_rqst <= '1';
						else
							bus_rqst <= '0';
							misc_val <= temp_iterator + 1;
						end if;


					when READ_IDLE =>
						if bus_data_ready = '1' then
							data_reg(temp_iterator) <= bus_data_send;
							temp_calc_chksum <= calc_chksum + to_integer(unsigned(bus_data_send(15 downto 8))) + to_integer(unsigned(bus_data_send(7 downto 0)));
						end if;

						if bus_enable = '0' then
							temp_iterator <= misc_val;
						end if;

						if bus_enable = '0' and misc_val = reg_cnt then
							temp_iterator    <= 0;
							misc_val         <= 0;
							tx_byte_index    <= 0;
						end if;


					when BUILD_PKT =>
						-- header
						tx_buf(0) <= x"7E";
						tx_buf(1) <= std_logic_vector(to_unsigned(4 + reg_cnt * 2, 8));  -- len
						tx_buf(2) <= x"0A";                                               -- write op_id
						tx_buf(3) <= std_logic_vector(to_unsigned(reg_cnt, 8));

						start_addr_tmp <= std_logic_vector(to_unsigned(start_addr, 16));

						tx_buf(4) <= start_addr_tmp(15 downto 8);
						tx_buf(5) <= start_addr_tmp(7 downto 0);

						-- data payload
						for i in 0 to 15 loop
							if i < reg_cnt then
								tx_buf(6 + i * 2)     <= data_reg(i)(15 downto 8);
								tx_buf(6 + i * 2 + 1) <= data_reg(i)(7 downto 0);
							end if;
						end loop;

						-- checksum
						tx_buf(6 + reg_cnt * 2) <= std_logic_vector(to_unsigned(255 - ((10 + reg_cnt + to_integer(unsigned(start_addr_tmp(15 downto 8))) + to_integer(unsigned(start_addr_tmp(7 downto 0))) + temp_calc_chksum) mod 256), 8));


						-- total bytes to send
						tx_len <= 7 + reg_cnt * 2;


					when SEND_DATA =>
						tx_start <= '1';
						tx_data  <= tx_buf(temp_iterator);

						if tx_busy = '1' then
							temp_iterator <= temp_iterator + 1;
						end if;

					when SEND_IDLE =>
						tx_start <= '0';

						if tx_busy = '0' then
							if temp_iterator = tx_len then
								temp_iterator <= 0;
							end if;
						end if;


                    when RESET_VALUES =>
                        --prev_state  <= (others => '0');
                        start_byte <= (others => '0');
                        pkt_len    <= (others => '0');
                        op_id      <= (others => '0');
                        checksum   <= (others => '0');
						tx_data    <= (others => '0');
						calc_chksum	 <= 0;
						prev_state		<= 0;
                        reg_cnt    		<= 0;
                        packet_byte_cnt <= 0;
						temp_iterator   <= 0;
                        misc_timer <= 0;
						misc_val <= 0;
						tx_byte_index <= 0;

                    when others =>
                        null;

                end case;
            end if;
        end if;
    end process;


--=======================================================
--================ COMBINATORIAL PROCESS ================
--=======================================================

    process(current_state, fifo_empty, start_byte, op_id, misc_timer, tx_busy, temp_iterator, data_byte_cnt, reg_cnt, prev_state, bus_enable, misc_val, checksum, calc_chksum)
    begin

		next_state      <= current_state;

        case current_state is

            when IDLE =>
                if fifo_empty = '0' then

                    if prev_state = 0 then
                        next_state <= GET_START;

                    elsif prev_state = 1 then
                        next_state <= GET_LEN;

                    elsif prev_state = 2 then
                        next_state <= GET_OP;

                    elsif prev_state = 3 then
                        next_state <= GET_REG_CNT;

                    elsif prev_state = 4 then
                        next_state <= GET_ADDR;

					elsif prev_state = 5 then
                        next_state <= GET_DATA;

					elsif prev_state = 6 then
                        next_state <= GET_CHCK_SUM;

                    end if;
                end if;

			when GET_ADDR =>
				if data_byte_cnt = 1 then
					next_state <= GET_ADDR;
				else
					next_state <= IDLE;
				end if;

			when GET_DATA =>
				if data_byte_cnt = 1 then
					next_state <= GET_DATA;
				else
					next_state <= IDLE;
				end if;

            when GET_CHCK_SUM =>
                next_state <= VERIFY_CHCK_SUM;

            when VERIFY_CHCK_SUM =>
                 if to_integer(unsigned(checksum)) = calc_chksum then
                    if op_id = x"0A" then
                        next_state <= ISSUE_IDLE;
                    elsif op_id = x"0F" then
                        next_state <= READ_BUS;
                    end if;
                else
                    next_state <= RESET_VALUES;
                end if;


			when ISSUE_BUS =>
				if bus_enable = '1' then
                    next_state <= ISSUE_IDLE;
                end if;

            when ISSUE_IDLE =>
				if temp_iterator = reg_cnt then
                    next_state <= RESET_VALUES;
                elsif bus_enable = '0' then
                    next_state <= ISSUE_BUS;
                end if;


			when READ_BUS =>
				if bus_enable = '1' then
                    next_state <= READ_IDLE;
                end if;

			when READ_IDLE =>
				if bus_enable = '0' then
					if misc_val = reg_cnt then
						next_state <= BUILD_PKT;
					else
						next_state <= READ_BUS;
					end if;
				end if;


			when BUILD_PKT =>
				next_state <= SEND_DATA;

			when SEND_DATA =>
				if tx_busy = '1' then
					next_state <= SEND_IDLE;
				end if;

			when SEND_IDLE =>
				if tx_busy = '0' then
					if temp_iterator = tx_len then
						next_state <= RESET_VALUES;
					else
						next_state <= SEND_DATA;
					end if;
				end if;

            when others =>
                next_state <= IDLE;

        end case;
    end process;
end architecture behavioral;










































-- ================================================================
-- ================================================================
-- ===================  TOP: RS232 MODULE  ========================
-- ================================================================
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rs232 is
    generic (
        --BAUD_DIV : integer;
		BAUD_DIV : integer := 2597;
        FIFO_DEPTH : integer := 16
    );
    port (
        -- Clock and reset
        clk : in  std_logic;
        rst : in  std_logic;

        -- External serial pins
        rx  : in  std_logic;
        tx  : out std_logic;

        -- Bus master interface
        bus_data_store	: out  std_logic_vector(15 downto 0);
		bus_data_send  : in  std_logic_vector(15 downto 0);
        bus_enable     : in  std_logic;
        bus_data_ready : in  std_logic;
        bus_cmd        : out std_logic;
        bus_addr       : out std_logic_vector(15 downto 0);
        bus_rqst       : out std_logic
    );
end entity rs232;

architecture structural of rs232 is

    -- ---------------------------------------------------------------
    -- Internal wiring
    -- ---------------------------------------------------------------

    -- RX baud generator
    signal baud_en_rx   : std_logic;
    signal baud_tick_rx : std_logic;

    -- TX baud generator
    signal baud_en_tx   : std_logic;
    signal baud_tick_tx : std_logic;

    -- RX output
    signal byte_save    : std_logic_vector(7 downto 0);
    signal byte_ready   : std_logic;

    -- FIFO
    signal fifo_read_en   : std_logic;
    signal fifo_read_data : std_logic_vector(7 downto 0);
    signal fifo_empty     : std_logic;

    -- TX
    signal tx_data  : std_logic_vector(7 downto 0);
    signal tx_start : std_logic;
    signal tx_busy  : std_logic;

begin

    -- ---------------------------------------------------------------
    -- RX baud generator
    -- ---------------------------------------------------------------
    U_BAUD_RX : entity work.baud_generator
        generic map (BAUD_DIV => BAUD_DIV)
        port map (
            clk    => clk,
            rst    => rst,
            enable => baud_en_rx,
            tick   => baud_tick_rx
        );

    -- ---------------------------------------------------------------
    -- TX baud generator
    -- ---------------------------------------------------------------
    U_BAUD_TX : entity work.baud_generator
        generic map (BAUD_DIV => BAUD_DIV)
        port map (
            clk    => clk,
            rst    => rst,
            enable => baud_en_tx,
            tick   => baud_tick_tx
        );

    -- ---------------------------------------------------------------
    -- UART RX
    -- ---------------------------------------------------------------
    U_RX : entity work.uart_rx
        port map (
            clk        => clk,
            rst        => rst,
            baud_en    => baud_en_rx,
            baud_tick  => baud_tick_rx,
            byte_save  => byte_save,
            byte_ready => byte_ready,
            rx         => rx
        );

    -- ---------------------------------------------------------------
    -- UART TX
    -- ---------------------------------------------------------------
    U_TX : entity work.uart_tx
        port map (
            clk       => clk,
            rst       => rst,
            baud_en   => baud_en_tx,
            baud_tick => baud_tick_tx,
            data_in   => tx_data,
            start     => tx_start,
            busy      => tx_busy,
            tx        => tx
        );

    -- ---------------------------------------------------------------
    -- FIFO
    -- ---------------------------------------------------------------
    U_FIFO : entity work.fifo
        generic map (DEPTH => FIFO_DEPTH)
        port map (
            clk        => clk,
            rst        => rst,
            write_en   => byte_ready,
            write_data => byte_save,
            read_en    => fifo_read_en,
            read_data  => fifo_read_data,
            empty      => fifo_empty
        );

    -- ---------------------------------------------------------------
    -- Decoder
    -- ---------------------------------------------------------------
    U_DECODER : entity work.decoder
        port map (
            clk            => clk,
            rst            => rst,
            fifo_read_data => fifo_read_data,
            fifo_empty     => fifo_empty,
            fifo_read_en   => fifo_read_en,
            bus_data_store => bus_data_store,
			bus_data_send  => bus_data_send,
            bus_enable     => bus_enable,
            bus_data_ready => bus_data_ready,
            bus_cmd        => bus_cmd,
            bus_addr       => bus_addr,
            bus_rqst       => bus_rqst,
            tx_data        => tx_data,
            tx_start       => tx_start,
            tx_busy        => tx_busy
        );

end architecture structural;
