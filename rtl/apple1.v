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
    input  clk14,               // 14 MHz master clock
    input  rst_n,               // active low synchronous reset (needed for simulation)

	 // RAM interface
	 output [15:0] ram_addr,
	 output  [7:0] ram_din,
	 input   [7:0] ram_dout,
	 output        ram_rd,
 	 output        ram_wr,

    // I/O interface to keyboard
    input ps2_clk,              // PS/2 keyboard serial clock input
    input ps2_din,              // PS/2 keyboard serial data input

    // Outputs to VGA display
    output vga_h_sync,          // hozizontal VGA sync pulse
    output vga_v_sync,          // vertical VGA sync pulse
    output vga_red,             // red VGA signal
    output vga_grn,             // green VGA signal
    output vga_blu,             // blue VGA signal
    input vga_cls               // clear screen button
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
    // Clocks

    wire cpu_clken;
    clock clock(
        .clk14(clk14),
        .rst_n(rst_n),
        .cpu_clken(cpu_clken)
    );

    //////////////////////////////////////////////////////////////////////////
    // Reset

    wire rst;
    pwr_reset pwr_reset(
        .clk14(clk14),
        .rst_n(rst_n),
        .enable(cpu_clken),
        .rst(rst)
    );

    //////////////////////////////////////////////////////////////////////////
    // 6502

    arlet_6502 arlet_6502(
        .clk    (clk14),
        .enable (cpu_clken),
        .rst    (rst),
        .ab     (addr),
        .dbi    (cpu_din),
        .dbo    (cpu_dout),
        .we     (we),
        .irq_n  (1'b1),
        .nmi_n  (1'b1),
        .ready  (cpu_clken)        
    );

    //////////////////////////////////////////////////////////////////////////
    // Address Decoding

    wire keyboard_cs = (addr[15:1]  == 15'b110100000001000);  // 0xD010 -> 0xD011
    wire display_cs  = (addr[15:1]  == 15'b110100000001001);  // 0xD012 -> 0xD013               
	 wire ram_cs = !keyboard_cs & !display_cs;

	 wire [7:0] display_dout = 8'b0;   // display always returns ready on the control port
	 
    //////////////////////////////////////////////////////////////////////////
    // RAM and ROM


    //////////////////////////////////////////////////////////////////////////
    // Peripherals

    // PS/2 keyboard interface
    wire [7:0] ps2_dout;
    ps2keyboard keyboard(
        .clk14(clk14),
        .rst(rst),
        .key_clk(ps2_clk),
        .key_din(ps2_din),
        .cs(keyboard_cs),
        .address(addr[0]),
        .dout(ps2_dout)
    );

    display display(
        .clk(clk14),
        .enable(display_cs & cpu_clken),
        .rst(rst),

        .vga_h_sync(vga_h_sync),
        .vga_v_sync(vga_v_sync),
        .vga_red(vga_red),
        .vga_grn(vga_grn),
        .vga_blu(vga_blu),

        .address(addr[0]),
        .w_en(we & display_cs),
        .din(cpu_dout),        
        .clr_screen(vga_cls)
    );

    //////////////////////////////////////////////////////////////////////////
    // CPU Data In MUX

    // link up chip selected device to cpu input
    assign cpu_din = display_cs  ? display_dout :
                     keyboard_cs ? ps2_dout     :
							ram_cs      ? ram_dout     :
							8'hFF;
endmodule
