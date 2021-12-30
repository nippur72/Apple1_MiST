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

    // I/O interface to computer
    input  uart_rx,             // asynchronous serial data input from computer
    output uart_tx,             // asynchronous serial data output to computer
    output uart_cts,            // clear to send flag to computer

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

    wire ram_cs      = (addr[15:13] ==  3'b000);              // 0x0000 -> 0x1FFF
    wire keyboard_cs = (addr[15:1]  == 15'b110100000001000);  // 0xD010 -> 0xD011
    wire display_cs  = (addr[15:1]  == 15'b110100000001001);  // 0xD012 -> 0xD013               
    wire basic_cs    = (addr[15:12] ==  4'b1110);             // 0xE000 -> 0xEFFF
    wire rom_cs      = (addr[15:8]  ==  8'b11111111);         // 0xFF00 -> 0xFFFF

	 wire [7:0] display_dout = 8'b0;   // display always returns ready on the control port
	 
    //////////////////////////////////////////////////////////////////////////
    // RAM and ROM

    // RAM
    wire [7:0] ram_dout;
    ram ram(
        .clk(clk14),
        .address(addr[12:0]),
        .w_en(we & ram_cs),
        .din(cpu_dout),
        .dout(ram_dout)
    );

    // WozMon ROM
    wire [7:0] rom_dout;
    rom_wozmon rom_wozmon(
        .clk(clk14),
        .address(addr[7:0]),
        .dout(rom_dout)
    );

    // Basic ROM
    wire [7:0] basic_dout;
    rom_basic rom_basic(
        .clk(clk14),
        .address(addr[11:0]),
        .dout(basic_dout)
    );

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

    vga vga(
        .clk14(clk14),
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
        .mode(2'b0),
        .fg_colour(3'd7),
        .bg_colour(3'd0),
        .clr_screen(vga_cls)
    );

    //////////////////////////////////////////////////////////////////////////
    // CPU Data In MUX

    // link up chip selected device to cpu input
    assign cpu_din = ram_cs      ? ram_dout     :
                     rom_cs      ? rom_dout     :
                     basic_cs    ? basic_dout   :
                     display_cs  ? display_dout :
                     keyboard_cs ? ps2_dout     :                 
                     8'hFF;
endmodule
