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

    arlet_6502 arlet_6502(
        .clk    (sys_clock),
        .enable (cpu_clken),
        .rst    (reset),
        .ab     (addr),
        .dbi    (cpu_din),
        .dbo    (cpu_dout),
        .we     (we),
        .irq_n  (INT_n),
        .nmi_n  (1'b1),
        .ready  (cpu_clken)        
    );

    //////////////////////////////////////////////////////////////////////////
    // Address Decoding

    wire keyboard_cs = (addr[15:1]  == 15'b110100000001000);  // 0xD010 -> 0xD011
    wire display_cs  = (addr[15:1]  == 15'b110100000001001);  // 0xD012 -> 0xD013               
	 wire ram_cs = !keyboard_cs & !display_cs;

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
    assign cpu_din = display_cs  ? display_dout :
                     keyboard_cs ? ps2_dout     :
							ram_cs      ? ram_dout     :
							8'hFF;
endmodule
