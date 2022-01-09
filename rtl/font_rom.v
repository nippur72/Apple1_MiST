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
// Description: 8KB RAM for system
//
// Author.....: Alan Garfield
// Date.......: 3-2-2018
//

module font_rom (
    input clk,              // clock signal    
    input [5:0] character,  // address bus
    input [2:0] pixel,      // address of the pixel to output
    input [4:0] line,       // address of the line to output
    output reg out          // single pixel from address and pixel pos
    );

    reg [7:0] rom[0:1023];
	 //reg [7:0] rom[0:511];

    initial
        $readmemh("roms/vga_font_bitreversed.hex", rom, 0, 1023);
		  //$readmemb("roms/s2513.bin", rom, 0, 511);

    // double height of pixel by ignoring bit 0
    wire [3:0] line_ptr = line[4:1];	 

    // Note: Quartus II reverses the pixels when we do:
    //
    // rom[address][bitindex] 
    //
    // directly, so we use an intermediate 
    // signal, romout, to work around this 
    // problem.
    //
    // IceCube2 and Yosys don't seem to have this problem.
    //
    
    reg [7:0] romout;
    
    always @(posedge clk)
    begin
        romout = rom[(character * 10) + {2'd0, line_ptr}];
		  //romout = rom[(character * 8) + {2'd0, line_ptr}];
        
        out <= romout[pixel];
    end

endmodule
     
