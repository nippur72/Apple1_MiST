// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
//
// Description: Apple1 hardware core
//
// Author.....: Alan Garfield
//              Niels A. Moseley
// Date.......: 26-1-2018
//

module apple1(
    input  reset,               // reset
	 
    input  sys_clock,           // system clock	 
	 input  pixel_clken,         // 7 MHz pixel clock 
	 input  cpu_clken,           // cpu clock enable
    
	 // RAM interface
	 output [15:0] ram_addr,
	 output  [7:0] ram_din,
	 input   [7:0] ram_dout,
	 output        ram_rd,
 	 output        ram_wr,

    // I/O interface to keyboard
    input ps2_clk,              // PS/2 keyboard serial clock input
    input ps2_din,              // PS/2 keyboard serial data input
	 
	 // interrupt signal
	 input INT_n,

    // video outputs
    output       vga_h_sync,          // hozizontal sync pulse
    output       vga_v_sync,          // vertical sync pulse
    output [5:0] vga_red,             // red signal
    output [5:0] vga_grn,             // green signal
    output [5:0] vga_blu,             // blue signal  
	 
	 output reset_key,           // keyboard shortcut for reset
	 output poweroff_key         // keyboard shortcut for poweroff/on
);

   assign ram_addr = addr;
   assign ram_din  = cpu_dout;
   assign ram_rd   = ram_cs;
   assign ram_wr   = we & ram_cs;  

    //////////////////////////////////////////////////////////////////////////
    // Registers and Wires

    wire [15:0] addr;
    wire [7:0] cpu_din;
    wire [7:0] cpu_dout;
    wire we;

    //////////////////////////////////////////////////////////////////////////
    // 6502
	
	 wire    R_W_n;	 	 
	 assign  we = ~R_W_n;
	 
	 // for debugging T65
	 wire [63:0] T65_regs;	 
	 wire [15:0] T65_A  = T65_regs[ 7: 0];
	 wire [15:0] T65_X  = T65_regs[15: 8];
	 wire [15:0] T65_Y  = T65_regs[23:16];
	 wire [15:0] T65_P  = T65_regs[31:24];
	 wire [15:0] T65_SP = T65_regs[39:32];
	 wire [23:0] T65_PC = T65_regs[63:40];
	 
	 T65 T65(
		 .Mode(2'b00),        // "00" => 6502, "01" => 65C02, "10" => 65C816		 
       .Res_n(~(reset & !cpu_arlet)),  
		 .Enable(cpu_clken & !cpu_arlet), 
		 .Clk(sys_clock),
		 .Rdy(1'b1),       
		 .IRQ_n(INT_n), 
		 .NMI_n(1'b1),		 
		 .R_W_n(R_W_n),   
		 .A(addr),             		 
		 .DI(R_W_n == 0 ? cpu_dout : cpu_din),   // T65 requires cpu_dout feed back in
		 .DO(cpu_dout),
		 .Regs(T65_regs)
	 );    			 	 	 	 
	 	 
    //////////////////////////////////////////////////////////////////////////
    // Address Decoding

    wire keyboard_cs = (addr[15:1]  == 15'b110100000001000);  // 0xD010 -> 0xD011
    wire display_cs  = (addr[15:1]  == 15'b110100000001001);  // 0xD012 -> 0xD013               
	 wire ram_cs = !keyboard_cs & !display_cs;
	 wire debug_cs = addr >= 16'hF000 && addr <= 16'hF007;
	 	 
	 wire [7:0] debug_dout = addr[7:0] == 0 ? T65_A         :        // A regs[ 7: 0]
									 addr[7:0] == 1 ? T65_X         :        // X regs[15: 8]
									 addr[7:0] == 2 ? T65_Y         :        // Y regs[23:16]
									 addr[7:0] == 3 ? T65_P         :        // P regs[31:24]
									 addr[7:0] == 4 ? T65_SP        :        // SP regs[39:32]
									 addr[7:0] == 5 ? T65_PC[ 7: 0] :        // PC regs[47:40]
									 addr[7:0] == 6 ? T65_PC[15: 8] :        // PC regs[55:48]
									 addr[7:0] == 7 ? T65_PC[23:16] : 8'hAA; // PC regs[63:56]
									                   	 
	 // byte returned from display out
	 wire [7:0] display_dout = { ~PB7, 7'b0 };  

    //////////////////////////////////////////////////////////////////////////
    // Peripherals

    // PS/2 keyboard interface
    wire [7:0] ps2_dout;
	 wire cls_key;
    ps2keyboard keyboard(
        .clk(sys_clock),
        .rst(reset),
        .key_clk(ps2_clk),
        .key_din(ps2_din),
        .cs(keyboard_cs),
        .address(addr[0]),
        .dout(ps2_dout),
		  .cls_key(cls_key),
		  .reset_key(reset_key),
		  .poweroff_key(poweroff_key)
    );

	 wire PB7; // (negated) display ready (PB7 of CIA)
    display display(
	     .reset(reset),
		  
        .sys_clock(sys_clock),
		  .pixel_clken(pixel_clken),
        .cpu_clken(cpu_clken & display_cs),        

        .vga_h_sync(vga_h_sync),
        .vga_v_sync(vga_v_sync),
        .vga_red(vga_red),
        .vga_grn(vga_grn),
        .vga_blu(vga_blu),

        .address(addr[0]),
        .w_en(we & display_cs),
        .din(cpu_dout),        
        .clr_screen(cls_key),
		  .ready(PB7)
    );

    //////////////////////////////////////////////////////////////////////////
    // CPU Data In MUX

    // link up chip selected device to cpu input
    assign cpu_din = debug_cs    ? debug_dout   :
	                  display_cs  ? display_dout :
                     keyboard_cs ? ps2_dout     :
							ram_cs      ? ram_dout     :							
							8'hFF;
							
endmodule
