//
// sdram.v
//
// sdram controller implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module sdram (

	// interface to the MT48LC16M16 chip
	inout [15:0]  		sd_data,    // 16 bit bidirectional data bus
	output [12:0]		sd_addr,    // 13 bit multiplexed address bus for row/col select
	output [1:0] 		sd_dqm,     // two byte masks
	output [1:0] 		sd_ba,      // four banks
	output 				sd_cs,      // chip select
	output 				sd_we,      // write enable
	output 				sd_ras,     // row address select
	output 				sd_cas,     // columns address select

	// cpu/chipset interface
	input 		 		init,			// init signal after FPGA config to initialize RAM
	input 		 		clk,			// sdram is accessed at up to 128MHz
	input					clkref,		// reference clock to sync to
	
	// input [2:0] q,
	
	input [7:0]  		din,			// data input from chipset/cpu
	output [7:0]      dout,			// data output to chipset/cpu
	input [24:0]   	addr,       // 25 bit byte address
	input 		 		oe,         // cpu/chipset requests read
	input 		 		we          // cpu/chipset requests write
);

// ---------------------------------------------------------------------
// ------------------------ sdram configuration ------------------------
// ---------------------------------------------------------------------
// MODE is sent as address on reset = 2
// PRECHARGE_ADDR is sent as address on reset = 13
localparam RASCAS_DELAY   = 3'd3;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write
localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 
localparam PRECHARGE_ADDR = 13'b0010000000000;

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

// there are 8 states (0-7) tracked by "q"

localparam STATE_IDLE      = 3'd0;                              // first state in cycle
localparam STATE_CMD_START = 3'd1;                              // state in which a new command can be started
localparam STATE_CMD_CONT  = STATE_CMD_START+RASCAS_DELAY-3'd1; // 4 command can be continued
localparam STATE_LAST      = 3'd7;                              // last state in cycle

reg [2:0] q /* synthesis noprune */;

always @(posedge clk) begin
	// 32Mhz counter synchronous to 4 Mhz clock
   // force counter to pass state 5->6 exactly after the rising edge of clkref
	// since clkref is two clocks early
   if(((q == 7) && ( clkref == 0)) ||
		((q == 0) && ( clkref == 1)) ||
      ((q != 7) && (q != 0)))
			q <= q + 3'd1;
end


// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
reg [4:0] reset;
always @(posedge clk) begin
	if(init)	reset <= 5'h1f;
	else if((q == STATE_LAST) && (reset != 0))
		reset <= reset - 5'd1;
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;    // initial state
localparam CMD_NOP             = 4'b0111;    // (not used here)
localparam CMD_ACTIVE          = 4'b0011;    // command starts, done at STATE_IDLE
localparam CMD_READ            = 4'b0101;    // read commanddone, done at STATE_CMD_CONT
localparam CMD_WRITE           = 4'b0100;    // write command, done at STATE_CMD_CONT
localparam CMD_BURST_TERMINATE = 4'b0110;    // (not used here)
localparam CMD_PRECHARGE       = 4'b0010;    // sends a precharge address, done when reset=13 and STATE_IDLE 
localparam CMD_AUTO_REFRESH    = 4'b0001;    // refresh command, done at STATE_IDLE
localparam CMD_LOAD_MODE       = 4'b0000;    // sends MODE (sdram config), done when reset=2 and STATE_IDLE

reg [3:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_cs  = sd_cmd[3];   // in negated logic
assign sd_ras = sd_cmd[2];   // in negated logic
assign sd_cas = sd_cmd[1];   // in negated logic
assign sd_we  = sd_cmd[0];   // in negated logic

assign sd_data = we ? {din, din} : 16'bZZZZZZZZZZZZZZZZ;

assign dout = sd_data[7:0];

always @(posedge clk) begin
	sd_cmd <= CMD_INHIBIT;

	if(reset != 0) begin
      // SDRAM is resetting, counting from 31 to 0
		if(q == STATE_IDLE) begin
			if(reset == 13)  sd_cmd <= CMD_PRECHARGE;
			if(reset ==  2)  sd_cmd <= CMD_LOAD_MODE;
		end
	end else begin
      // normal run
		if(q == STATE_IDLE) begin
			if(we || oe) sd_cmd <= CMD_ACTIVE;
			else         sd_cmd <= CMD_AUTO_REFRESH;
		end       
      else if(q == STATE_CMD_CONT) begin
			if(we)		 sd_cmd <= CMD_WRITE;
			else if(oe)  sd_cmd <= CMD_READ;
		end
	end
end

// address during reset	
wire [12:0] reset_addr = (reset == 13) ? PRECHARGE_ADDR : MODE;

// address during normal run
wire [12:0] row = addr[20:8];
wire [12:0] col = { 4'b0010, addr[23], addr[7:0] };
wire [12:0] run_addr = (q == STATE_CMD_START)? row : col;

assign sd_addr = (reset != 0) ? reset_addr : run_addr;
assign sd_ba = addr[22:21]; // bank is taken from cpu address high bits
assign sd_dqm = 2'b00;      // no mask

endmodule
